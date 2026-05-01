public with sharing class ErrorLogManagerController {

    @AuraEnabled(cacheable=true)
    public static String getLogPayload(Id logId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :logId
            ORDER BY Id DESC
            LIMIT 1
        ];
        if (links.isEmpty()) return null;
        ContentVersion cv = links[0].ContentDocument.LatestPublishedVersion;
        if (cv == null) return null;
        return cv.VersionData.toString();
    }

    @AuraEnabled
    public static void updatePayloadAndRetry(Id logId, String payloadJson) {
        try {
            new RetryWriter().execute(logId, payloadJson);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // without sharing mirrors LogWriter — ContentDocumentLink inserts can fail
    // under restrictive file-sharing settings if run with caller's sharing context.
    private without sharing class RetryWriter {
        void execute(Id logId, String payloadJson) {
            ContentVersion cv = new ContentVersion(
                Title          = 'error_payload',
                PathOnClient   = 'error_payload.json',
                VersionData    = Blob.valueOf(payloadJson),
                IsMajorVersion = true
            );
            insert cv;

            Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            insert new ContentDocumentLink(
                LinkedEntityId    = logId,
                ContentDocumentId = docId,
                ShareType         = 'V'
            );

            update new Error_Log__c(Id = logId, Status__c = 'Retry');
        }
    }
}
