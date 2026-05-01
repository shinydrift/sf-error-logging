@IsTest
private class ErrorLogManagerControllerTest {

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static Error_Log__c insertLog() {
        Error_Log__c log = new Error_Log__c(
            Object_Type__c = 'Account',
            Operation__c   = 'INSERT',
            Error_Count__c = 1,
            Status__c      = 'Open'
        );
        insert log;
        return log;
    }

    private static void attachPayload(Id logId, String payloadJson) {
        ContentVersion cv = new ContentVersion(
            Title          = 'error_payload',
            PathOnClient   = 'error_payload.json',
            VersionData    = Blob.valueOf(payloadJson),
            IsMajorVersion = true
        );
        insert cv;
        cv = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
        insert new ContentDocumentLink(
            LinkedEntityId    = logId,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType         = 'V'
        );
    }

    // ── getLogPayload ─────────────────────────────────────────────────────────

    @IsTest
    static void getLogPayload_withAttachment_returnsJson() {
        Error_Log__c log = insertLog();
        String payload = '{"records":[],"errors":[]}';
        attachPayload(log.Id, payload);

        Test.startTest();
        String result = ErrorLogManagerController.getLogPayload(log.Id);
        Test.stopTest();

        Assert.areEqual(payload, result);
    }

    @IsTest
    static void getLogPayload_noAttachment_returnsNull() {
        Error_Log__c log = insertLog();

        Test.startTest();
        String result = ErrorLogManagerController.getLogPayload(log.Id);
        Test.stopTest();

        Assert.isNull(result);
    }

    @IsTest
    static void getLogPayload_multipleAttachments_returnsLatest() {
        Error_Log__c log = insertLog();
        attachPayload(log.Id, '{"records":[],"errors":[],"version":1}');
        attachPayload(log.Id, '{"records":[],"errors":[],"version":2}');

        Test.startTest();
        String result = ErrorLogManagerController.getLogPayload(log.Id);
        Test.stopTest();

        Assert.isTrue(result.contains('"version":2'), 'expected the latest attachment to be returned');
    }

    // ── updatePayloadAndRetry ─────────────────────────────────────────────────

    @IsTest
    static void updatePayloadAndRetry_createsAttachmentAndSetsRetry() {
        // Status 'Failed' prevents the ErrorLogTrigger (Open→Retry guard) from firing,
        // so we can assert the controller's own Status__c='Retry' write in isolation.
        Error_Log__c log = new Error_Log__c(
            Object_Type__c = 'Account',
            Operation__c   = 'INSERT',
            Error_Count__c = 1,
            Status__c      = 'Failed'
        );
        insert log;
        String newPayload = '{"records":[{"Name":"Retry Account"}],"errors":[]}';

        Test.startTest();
        ErrorLogManagerController.updatePayloadAndRetry(log.Id, newPayload);
        Test.stopTest();

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :log.Id
        ];
        Assert.areEqual(1, links.size(), 'expected one ContentDocumentLink');
        String stored = links[0].ContentDocument.LatestPublishedVersion.VersionData.toString();
        Assert.areEqual(newPayload, stored);

        log = [SELECT Status__c FROM Error_Log__c WHERE Id = :log.Id];
        Assert.areEqual('Retry', log.Status__c);
    }

    @IsTest
    static void updatePayloadAndRetry_invalidLogId_throwsAuraHandledException() {
        // Fabricate a well-formed but non-existent Error_Log__c Id so the update DML fails.
        Id bogusId = Error_Log__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        String payload = '{"records":[],"errors":[]}';

        Test.startTest();
        try {
            ErrorLogManagerController.updatePayloadAndRetry(bogusId, payload);
            Assert.fail('expected AuraHandledException');
        } catch (AuraHandledException e) {
            // reaching here confirms the exception was wrapped and re-thrown correctly
        }
        Test.stopTest();
    }
}
