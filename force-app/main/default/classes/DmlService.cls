/**
 * DmlService
 *
 * Centralised DML utility that uses the Database class for granular control.
 * Partial success is the default for all operations — pass allOrNone=true to
 * override. Any record-level failures are captured in a single Error_Log__c
 * per method call, with the full record and error detail attached as a JSON
 * ContentVersion file linked to the log record.
 */
public without sharing class DmlService {

    private static final String OP_INSERT = 'INSERT';
    private static final String OP_UPDATE = 'UPDATE';
    private static final String OP_UPSERT = 'UPSERT';
    private static final String OP_DELETE = 'DELETE';

    public static Database.SaveResult[] insertRecords(List<SObject> records) {
        return insertRecords(records, false);
    }

    public static Database.SaveResult[] insertRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        Database.SaveResult[] results = Database.insert(records, allOrNone);
        processSaveResults(records, results, OP_INSERT);
        return results;
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records) {
        return updateRecords(records, false);
    }

    public static Database.SaveResult[] updateRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        Database.SaveResult[] results = Database.update(records, allOrNone);
        processSaveResults(records, results, OP_UPDATE);
        return results;
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records) {
        return upsertRecords(records, false);
    }

    public static Database.UpsertResult[] upsertRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.UpsertResult>();
        }
        Database.UpsertResult[] results = Database.upsert(records, allOrNone);
        processUpsertResults(records, results, OP_UPSERT);
        return results;
    }

    public static Database.DeleteResult[] deleteRecords(List<SObject> records) {
        return deleteRecords(records, false);
    }

    public static Database.DeleteResult[] deleteRecords(List<SObject> records, Boolean allOrNone) {
        if (records == null || records.isEmpty()) {
            return new List<Database.DeleteResult>();
        }
        Database.DeleteResult[] results = Database.delete(records, allOrNone);
        processDeleteResults(records, results, OP_DELETE);
        return results;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static void processSaveResults(
        List<SObject> records,
        Database.SaveResult[] results,
        String operation
    ) {
        List<SObject> failed = new List<SObject>();
        List<Map<String, Object>> details = new List<Map<String, Object>>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        String typeName = '';

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                SObject rec = records[i];
                if (String.isBlank(typeName)) {
                    typeName = resolveTypeName(rec, typeCache);
                }
                failed.add(rec);
                details.add(toErrorDetail(rec.Id, results[i].getErrors()));
            }
        }
        if (!failed.isEmpty()) {
            persistLog(typeName, operation, failed, details);
        }
    }

    private static void processUpsertResults(
        List<SObject> records,
        Database.UpsertResult[] results,
        String operation
    ) {
        List<SObject> failed = new List<SObject>();
        List<Map<String, Object>> details = new List<Map<String, Object>>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        String typeName = '';

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                SObject rec = records[i];
                if (String.isBlank(typeName)) {
                    typeName = resolveTypeName(rec, typeCache);
                }
                failed.add(rec);
                details.add(toErrorDetail(rec.Id, results[i].getErrors()));
            }
        }
        if (!failed.isEmpty()) {
            persistLog(typeName, operation, failed, details);
        }
    }

    private static void processDeleteResults(
        List<SObject> records,
        Database.DeleteResult[] results,
        String operation
    ) {
        List<SObject> failed = new List<SObject>();
        List<Map<String, Object>> details = new List<Map<String, Object>>();
        Map<Schema.SObjectType, String> typeCache = new Map<Schema.SObjectType, String>();
        String typeName = '';

        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                SObject rec = records[i];
                if (String.isBlank(typeName)) {
                    typeName = resolveTypeName(rec, typeCache);
                }
                failed.add(rec);
                details.add(toErrorDetail(rec.Id, results[i].getErrors()));
            }
        }
        if (!failed.isEmpty()) {
            persistLog(typeName, operation, failed, details);
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

    private static void persistLog(
        String typeName,
        String operation,
        List<SObject> failedRecords,
        List<Map<String, Object>> errorDetails
    ) {
        Error_Log__c log = new Error_Log__c(
            Object_Type__c = typeName,
            Operation__c   = operation,
            Error_Count__c = failedRecords.size(),
            Status__c      = 'Open'
        );
        Database.SaveResult logResult = Database.insert(log, false);
        if (!logResult.isSuccess()) {
            System.debug(LoggingLevel.ERROR, 'DmlService: failed to insert Error_Log__c: ' + logResult.getErrors());
            return;
        }
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
        Database.insert(cdl, false);
    }

    private static String resolveTypeName(SObject record, Map<Schema.SObjectType, String> typeCache) {
        Schema.SObjectType soType = record.getSObjectType();
        if (!typeCache.containsKey(soType)) {
            typeCache.put(soType, soType.getDescribe().getName());
        }
        return typeCache.get(soType);
    }
}
