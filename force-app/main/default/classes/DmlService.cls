/**
 * DmlService
 *
 * Centralised DML utility that uses the Database class for granular control.
 * Partial success is the default for all operations — pass allOrNone=true to
 * override. Any record-level failures are captured in a single Error_Log__c
 * per method call, with the full record and error detail attached as a JSON
 * ContentVersion file linked to the log record.
 *
 * NOTE: allOrNone=true throws DmlException before results are returned, so no
 * Error_Log__c record is created in that case. Callers using allOrNone=true
 * must handle the exception themselves.
 */
public inherited sharing class DmlService {

    // Populated by LogWriter so callers (e.g. ErrorLogRetryHandler) can link
    // newly created Error_Log__c records back to a parent.
    // Call clearRecentLogIds() before any operation you intend to inspect.
    public static List<Id> recentLogIds = new List<Id>();

    private static final String OP_INSERT = 'INSERT';
    private static final String OP_UPDATE = 'UPDATE';
    private static final String OP_UPSERT = 'UPSERT';
    private static final String OP_DELETE = 'DELETE';

    // ── Insert ────────────────────────────────────────────────────────────────

    public static Database.SaveResult[] insertRecords(List<SObject> records) {
        return insertRecords(records, false);
    }

    public static Database.SaveResult[] insertRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) return new List<Database.SaveResult>();
        Database.SaveResult[] results = Database.insert(records, allOrNone);
        processResults(records, wrapSave(results), OP_INSERT);
        return results;
    }

    public static Database.SaveResult[] insertRecords(List<SObject> records, Database.DMLOptions options) {
        if (records == null || records.isEmpty()) return new List<Database.SaveResult>();
        Database.SaveResult[] results = Database.insert(records, options);
        processResults(records, wrapSave(results), OP_INSERT);
        return results;
    }

    // ── Update ────────────────────────────────────────────────────────────────

    public static Database.SaveResult[] updateRecords(List<SObject> records) {
        return updateRecords(records, false);
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) return new List<Database.SaveResult>();
        Database.SaveResult[] results = Database.update(records, allOrNone);
        processResults(records, wrapSave(results), OP_UPDATE);
        return results;
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records, Database.DMLOptions options) {
        if (records == null || records.isEmpty()) return new List<Database.SaveResult>();
        Database.SaveResult[] results = Database.update(records, options);
        processResults(records, wrapSave(results), OP_UPDATE);
        return results;
    }

    // ── Upsert ────────────────────────────────────────────────────────────────

    public static Database.UpsertResult[] upsertRecords(List<SObject> records) {
        return upsertRecords(records, false);
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) return new List<Database.UpsertResult>();
        Database.UpsertResult[] results = Database.upsert(records, allOrNone);
        processResults(records, wrapUpsert(results), OP_UPSERT);
        return results;
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records, Schema.SObjectField externalIdField) {
        return upsertRecords(records, externalIdField, false);
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records, Schema.SObjectField externalIdField, Boolean allOrNone) {
        if (records == null || records.isEmpty()) return new List<Database.UpsertResult>();
        Database.UpsertResult[] results = Database.upsert(records, externalIdField, allOrNone);
        processResults(records, wrapUpsert(results), OP_UPSERT);
        return results;
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    public static Database.DeleteResult[] deleteRecords(List<SObject> records) {
        return deleteRecords(records, false);
    }

    public static Database.DeleteResult[] deleteRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) return new List<Database.DeleteResult>();
        Database.DeleteResult[] results = Database.delete(records, allOrNone);
        processResults(records, wrapDelete(results), OP_DELETE);
        return results;
    }

    // ── Utility ───────────────────────────────────────────────────────────────

    public static void clearRecentLogIds() {
        recentLogIds.clear();
    }

    // ── Private: result wrapper interface ─────────────────────────────────────

    private interface DmlResultWrapper {
        Boolean isSuccess();
        List<Database.Error> getErrors();
    }

    private class SaveResultWrapper implements DmlResultWrapper {
        private Database.SaveResult r;
        SaveResultWrapper(Database.SaveResult r) { this.r = r; }
        public Boolean isSuccess() { return r.isSuccess(); }
        public List<Database.Error> getErrors() { return r.getErrors(); }
    }

    private class UpsertResultWrapper implements DmlResultWrapper {
        private Database.UpsertResult r;
        UpsertResultWrapper(Database.UpsertResult r) { this.r = r; }
        public Boolean isSuccess() { return r.isSuccess(); }
        public List<Database.Error> getErrors() { return r.getErrors(); }
    }

    private class DeleteResultWrapper implements DmlResultWrapper {
        private Database.DeleteResult r;
        DeleteResultWrapper(Database.DeleteResult r) { this.r = r; }
        public Boolean isSuccess() { return r.isSuccess(); }
        public List<Database.Error> getErrors() { return r.getErrors(); }
    }

    private static List<DmlResultWrapper> wrapSave(Database.SaveResult[] results) {
        List<DmlResultWrapper> wrapped = new List<DmlResultWrapper>();
        for (Database.SaveResult r : results) wrapped.add(new SaveResultWrapper(r));
        return wrapped;
    }

    private static List<DmlResultWrapper> wrapUpsert(Database.UpsertResult[] results) {
        List<DmlResultWrapper> wrapped = new List<DmlResultWrapper>();
        for (Database.UpsertResult r : results) wrapped.add(new UpsertResultWrapper(r));
        return wrapped;
    }

    private static List<DmlResultWrapper> wrapDelete(Database.DeleteResult[] results) {
        List<DmlResultWrapper> wrapped = new List<DmlResultWrapper>();
        for (Database.DeleteResult r : results) wrapped.add(new DeleteResultWrapper(r));
        return wrapped;
    }

    // ── Private: result processing ────────────────────────────────────────────

    private static void processResults(
        List<SObject> records,
        List<DmlResultWrapper> results,
        String operation
    ) {
        List<SObject> failed = new List<SObject>();
        List<Map<String, Object>> details = new List<Map<String, Object>>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        Set<String> typeNames = new Set<String>();

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                SObject rec = records[i];
                typeNames.add(resolveTypeName(rec, typeCache));
                failed.add(rec);
                details.add(toErrorDetail(rec.Id, results[i].getErrors()));
            }
        }
        if (!failed.isEmpty()) {
            String typeName = String.join(new List<String>(typeNames), ', ');
            LogWriter.write(typeName, operation, failed, details);
        }
    }

    private static Map<String, Object> toErrorDetail(Id recordId, List<Database.Error> errors) {
        List<String> messages    = new List<String>();
        List<String> statusCodes = new List<String>();
        List<String> fields      = new List<String>();

        for (Database.Error err : errors) {
            messages.add(err.getMessage());
            statusCodes.add(err.getStatusCode().name());
            if (!err.getFields().isEmpty()) {
                fields.add(String.join(err.getFields(), ', '));
            }
        }
        return new Map<String, Object>{
            'recordId'    => recordId,
            'messages'    => messages,
            'statusCodes' => statusCodes,
            'fields'      => fields
        };
    }

    private static String resolveTypeName(SObject record, Map<Schema.SObjectType, String> typeCache) {
        Schema.SObjectType soType = record.getSObjectType();
        if (!typeCache.containsKey(soType)) {
            typeCache.put(soType, soType.getDescribe().getName());
        }
        return typeCache.get(soType);
    }

    // ── Inner class: without sharing scoped to error log DML only ─────────────

    private without sharing class LogWriter {

        static void write(
            String typeName,
            String operation,
            List<SObject> failedRecords,
            List<Map<String, Object>> errorDetails
        ) {
            String firstStatusCode = '';
            if (!errorDetails.isEmpty()) {
                List<String> codes = (List<String>) errorDetails[0].get('statusCodes');
                if (codes != null && !codes.isEmpty()) {
                    firstStatusCode = codes[0].left(255);
                }
            }

            Error_Log__c log = new Error_Log__c(
                Object_Type__c    = typeName,
                Operation__c      = operation,
                Error_Count__c    = failedRecords.size(),
                Status__c         = 'Open',
                Running_User__c   = UserInfo.getUserId(),
                Stack_Trace__c    = new DmlException().getStackTraceString(),
                Transaction_Id__c = Request.getRequestId(),
                Status_Code__c    = firstStatusCode
            );
            Database.SaveResult logResult = Database.insert(log, false);
            if (!logResult.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'DmlService: failed to insert Error_Log__c: ' + logResult.getErrors());
                return;
            }
            DmlService.recentLogIds.add(log.Id);
            attachPayload(log.Id, failedRecords, errorDetails);
        }

        private static void attachPayload(
            Id logId,
            List<SObject> failedRecords,
            List<Map<String, Object>> errorDetails
        ) {
            Map<String, Object> payload = new Map<String, Object>{
                'records' => failedRecords,
                'errors'  => errorDetails
            };
            ContentVersion cv = new ContentVersion(
                Title          = 'error_payload',
                PathOnClient   = 'error_payload.json',
                VersionData    = Blob.valueOf(JSON.serialize(payload)),
                IsMajorVersion = true
            );
            Database.SaveResult cvResult = Database.insert(cv, false);
            if (!cvResult.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'DmlService: failed to insert ContentVersion: ' + cvResult.getErrors());
                return;
            }
            ContentVersion inserted = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cvResult.getId()];
            ContentDocumentLink cdl = new ContentDocumentLink(
                LinkedEntityId    = logId,
                ContentDocumentId = inserted.ContentDocumentId,
                ShareType         = 'V'
            );
            Database.SaveResult cdlResult = Database.insert(cdl, false);
            if (!cdlResult.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'DmlService: failed to insert ContentDocumentLink: ' + cdlResult.getErrors());
            }
        }
    }
}
