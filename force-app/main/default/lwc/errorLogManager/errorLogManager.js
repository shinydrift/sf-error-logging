import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { RefreshEvent } from 'lightning/refresh';
import getLogPayload from '@salesforce/apex/ErrorLogManagerController.getLogPayload';
import updatePayloadAndRetry from '@salesforce/apex/ErrorLogManagerController.updatePayloadAndRetry';

// Fields added by the component — never sent back to Apex
const INTERNAL_FIELDS = new Set(['attributes', '_rowKey', '_errorMessages']);

export default class ErrorLogManager extends LightningElement {
    @api recordId;

    @track columns = [];
    @track tableData = [];
    @track draftValues = [];
    @track isSubmitting = false;

    isLoading = true;
    error;

    _wiredPayloadResult;
    _payloadErrors = [];

    get hasRecords() {
        return this.tableData.length > 0;
    }

    @wire(getLogPayload, { logId: '$recordId' })
    wiredPayload(result) {
        this._wiredPayloadResult = result;
        const { data, error } = result;
        if (data !== undefined) {
            this.isLoading = false;
            this.error = null;
            if (data) this._parsePayload(data);
        } else if (error) {
            this.isLoading = false;
            this.error = error.body?.message ?? 'Failed to load payload.';
        }
        // else: wire still pending — leave isLoading = true
    }

    _parsePayload(payloadJson) {
        let payload;
        try {
            payload = JSON.parse(payloadJson);
        } catch {
            this.error = 'Payload JSON is invalid.';
            return;
        }

        const records = payload.records ?? [];
        this._payloadErrors = payload.errors ?? [];

        if (!records.length) return;

        const fieldKeys = Object.keys(records[0]).filter(k => !INTERNAL_FIELDS.has(k));

        this.columns = [
            {
                label: 'Error',
                fieldName: '_errorMessages',
                type: 'text',
                editable: false,
                wrapText: true,
                initialWidth: 220
            },
            ...fieldKeys.map(key => ({
                label: key,
                fieldName: key,
                type: 'text',
                editable: key.toLowerCase() !== 'id'
            }))
        ];

        this.tableData = records.map((rec, i) => {
            const msgs = this._payloadErrors[i]?.messages?.join('; ') ?? '';
            const flat = Object.fromEntries(
                Object.entries(rec)
                    .filter(([k]) => !INTERNAL_FIELDS.has(k))
                    .map(([k, v]) => [k, v == null ? '' : String(v)])
            );
            return { ...flat, _rowKey: rec.Id ?? String(i), _errorMessages: msgs };
        });
    }

    handleInlineSave(event) {
        const drafts = event.detail.draftValues;
        this.tableData = this.tableData.map(row => {
            const draft = drafts.find(d => d._rowKey === row._rowKey);
            return draft ? { ...row, ...draft } : row;
        });
        this.draftValues = [];
    }

    async handleRetry() {
        this.isSubmitting = true;
        try {
            const cleanRecords = this.tableData.map(row =>
                Object.fromEntries(
                    Object.entries(row)
                        .filter(([k]) => !INTERNAL_FIELDS.has(k))
                        .map(([k, v]) => [k, v === '' ? null : v])
                )
            );

            await updatePayloadAndRetry({
                logId: this.recordId,
                payloadJson: JSON.stringify({ records: cleanRecords, errors: this._payloadErrors })
            });

            this.dispatchEvent(new ShowToastEvent({
                title: 'Submitted',
                message: 'Retry triggered. The page will refresh with the updated status.',
                variant: 'success'
            }));

            this.draftValues = [];
            await refreshApex(this._wiredPayloadResult);
            this.dispatchEvent(new RefreshEvent());
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Retry Failed',
                message: e.body?.message ?? 'An unexpected error occurred.',
                variant: 'error'
            }));
        } finally {
            this.isSubmitting = false;
        }
    }
}
