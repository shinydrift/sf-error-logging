/**
 * DmlRetryQueueable
 *
 * Enqueued by ErrorLogTrigger when an Error_Log__c Status__c changes to 'Retry'.
 * Reads the attached JSON payload (records + error details), re-runs the original
 * DML operation via DmlService, then updates the log status:
 *   - All records succeed  → Resolved
 *   - Any record fails     → Failed, Retry_Count__c incremented
 *                            (DmlService automatically logs the new failures)
 */
public class DmlRetryQueueable implements Queueable {

    private static final String OP_INSERT = 'INSERT';
    private static final String OP_UPDATE = 'UPDATE';
    private static final String OP_UPSERT = 'UPSERT';
    private static final String OP_DELETE = 'DELETE';

    private final Id logId;

    public DmlRetryQueueable(Id logId) {
        this.logId = logId;
    }

    public void execute(QueueableContext ctx) {
        Error_Log__c log = [
            SELECT Id, Object_Type__c, Operation__c, Retry_Count__c, Status__c
            FROM Error_Log__c
            WHERE Id = :logId
        ];

        // Mark as in-flight so a second Status__c='Retry' save won't re-enqueue
        log.Status__c = 'Retrying';
        update log;

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :logId
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];

        if (links.isEmpty()) {
            log.Status__c = 'Failed';
            update log;
            return;
        }

        String jsonStr = links[0].ContentDocument.LatestPublishedVersion.VersionData.toString();
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        List<Object> rawRecords = (List<Object>) payload.get('records');

        Type listType = Type.forName('List<' + log.Object_Type__c + '>');
        if (listType == null) {
            System.debug(LoggingLevel.ERROR, 'DmlRetryQueueable: unresolvable type ' + log.Object_Type__c);
            log.Status__c = 'Failed';
            update log;
            return;
        }
        List<SObject> records = (List<SObject>) JSON.deserialize(JSON.serialize(rawRecords), listType);

        Boolean allSuccess = runOperation(log.Operation__c, records);

        log.Status__c      = allSuccess ? 'Resolved' : 'Failed';
        log.Retry_Count__c = (log.Retry_Count__c == null ? 0 : log.Retry_Count__c) + 1;
        update log;
    }

    private Boolean runOperation(String operation, List<SObject> records) {
        if (operation == OP_INSERT) {
            return allSaveSucceeded(DmlService.insertRecords(records));
        } else if (operation == OP_UPDATE) {
            return allSaveSucceeded(DmlService.updateRecords(records));
        } else if (operation == OP_UPSERT) {
            for (Database.UpsertResult r : DmlService.upsertRecords(records)) {
                if (!r.isSuccess()) return false;
            }
            return true;
        } else if (operation == OP_DELETE) {
            for (Database.DeleteResult r : DmlService.deleteRecords(records)) {
                if (!r.isSuccess()) return false;
            }
            return true;
        }
        return false;
    }

    private Boolean allSaveSucceeded(Database.SaveResult[] results) {
        for (Database.SaveResult r : results) {
            if (!r.isSuccess()) return false;
        }
        return true;
    }
}
