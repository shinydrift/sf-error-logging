@IsTest
private class DmlServiceTest {

    // ── INSERT ───────────────────────────────────────────────────────────────

    @IsTest
    static void insertRecords_success_noLogs() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Test A'),
            new Account(Name = 'Test B')
        };

        Test.startTest();
        Database.SaveResult[] results = DmlService.insertRecords(accounts);
        Test.stopTest();

        Assert.areEqual(2, results.size());
        for (Database.SaveResult r : results) {
            Assert.isTrue(r.isSuccess());
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    @IsTest
    static void insertRecords_partial_logsOneEntry() {
        Account good = new Account(Name = 'Good Account');
        Account bad  = new Account(); // missing required Name

        DmlService.clearRecentLogIds();

        Test.startTest();
        Database.SaveResult[] results = DmlService.insertRecords(
            new List<Account>{ good, bad }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());

        List<Error_Log__c> logs = [
            SELECT Operation__c, Object_Type__c, Error_Count__c, Status__c,
                   Running_User__c, Transaction_Id__c, Status_Code__c
            FROM Error_Log__c
        ];
        Assert.areEqual(1, logs.size(), 'Expected one log entry per method call');
        Assert.areEqual('INSERT', logs[0].Operation__c);
        Assert.areEqual('Account', logs[0].Object_Type__c);
        Assert.areEqual(1, (Integer) logs[0].Error_Count__c);
        Assert.areEqual('Open', logs[0].Status__c);
        Assert.areEqual(UserInfo.getUserId(), logs[0].Running_User__c);
        Assert.isNotNull(logs[0].Transaction_Id__c);
        Assert.isNotNull(logs[0].Status_Code__c);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :logs[0].Id]);

        Assert.areEqual(1, DmlService.recentLogIds.size());
        Assert.areEqual(logs[0].Id, DmlService.recentLogIds[0]);
    }

    @IsTest
    static void insertRecords_partial_payloadContainsErrorDetails() {
        Account bad = new Account(); // missing required Name

        Test.startTest();
        DmlService.insertRecords(new List<Account>{ bad });
        Test.stopTest();

        Error_Log__c log = [SELECT Id FROM Error_Log__c LIMIT 1];
        ContentDocumentLink cdl = [
            SELECT ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :log.Id
            LIMIT 1
        ];
        ContentVersion cv = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :cdl.ContentDocument.LatestPublishedVersionId
        ];

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(cv.VersionData.toString());
        Assert.isTrue(payload.containsKey('records'));
        Assert.isTrue(payload.containsKey('errors'));

        List<Object> errors = (List<Object>) payload.get('errors');
        Assert.areEqual(1, errors.size());

        Map<String, Object> errorDetail = (Map<String, Object>) errors[0];
        List<Object> statusCodes = (List<Object>) errorDetail.get('statusCodes');
        Assert.isFalse(statusCodes.isEmpty());
    }

    @IsTest
    static void insertRecords_allOrNone_propagatesException() {
        Account bad = new Account(); // missing Name

        Test.startTest();
        try {
            DmlService.insertRecords(new List<Account>{ bad }, true);
            Assert.fail('Expected DmlException not thrown');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('REQUIRED_FIELD_MISSING'));
        }
        Test.stopTest();
    }

    @IsTest
    static void insertRecords_nullInput_returnsEmpty() {
        Test.startTest();
        Database.SaveResult[] results = DmlService.insertRecords(null);
        Test.stopTest();

        Assert.areEqual(0, results.size());
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    // ── UPDATE ───────────────────────────────────────────────────────────────

    @IsTest
    static void updateRecords_success_noLogs() {
        Account a = new Account(Name = 'Before');
        insert a;
        a.Name = 'After';

        Test.startTest();
        Database.SaveResult[] results = DmlService.updateRecords(new List<Account>{ a });
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    @IsTest
    static void updateRecords_partial_logsOneEntry() {
        Account real = new Account(Name = 'Real');
        insert real;

        Account ghost = new Account(Id = '001000000000000AAA', Name = 'Ghost');

        Test.startTest();
        Database.SaveResult[] results = DmlService.updateRecords(
            new List<Account>{ real, ghost }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());

        List<Error_Log__c> logs = [SELECT Error_Count__c, Status__c FROM Error_Log__c WHERE Operation__c = 'UPDATE'];
        Assert.areEqual(1, logs.size());
        Assert.areEqual(1, (Integer) logs[0].Error_Count__c);
        Assert.areEqual('Open', logs[0].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :logs[0].Id]);
    }

    @IsTest
    static void updateRecords_allOrNone_propagatesException() {
        Account ghost = new Account(Id = '001000000000000AAA', Name = 'Ghost');

        Test.startTest();
        try {
            DmlService.updateRecords(new List<Account>{ ghost }, true);
            Assert.fail('Expected DmlException not thrown');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains('ENTITY_IS_DELETED') ||
                e.getMessage().contains('INVALID_CROSS_REFERENCE_KEY') ||
                e.getMessage().contains('NOT_FOUND') ||
                e.getNumDml() > 0,
                'Expected a DML error for non-existent record, got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ── UPSERT ───────────────────────────────────────────────────────────────

    @IsTest
    static void upsertRecords_success_noLogs() {
        Account a = new Account(Name = 'Upsert Me');

        Test.startTest();
        Database.UpsertResult[] results = DmlService.upsertRecords(new List<Account>{ a });
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.isTrue(results[0].isCreated());
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    @IsTest
    static void upsertRecords_partial_logsOneEntry() {
        Account good = new Account(Name = 'Good');
        Account bad  = new Account(); // missing Name

        Test.startTest();
        Database.UpsertResult[] results = DmlService.upsertRecords(
            new List<Account>{ good, bad }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());

        List<Error_Log__c> logs = [SELECT Error_Count__c, Status__c FROM Error_Log__c WHERE Operation__c = 'UPSERT'];
        Assert.areEqual(1, logs.size());
        Assert.areEqual(1, (Integer) logs[0].Error_Count__c);
        Assert.areEqual('Open', logs[0].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :logs[0].Id]);
    }

    @IsTest
    static void upsertRecords_allOrNone_propagatesException() {
        Account bad = new Account(); // missing Name

        Test.startTest();
        try {
            DmlService.upsertRecords(new List<Account>{ bad }, true);
            Assert.fail('Expected DmlException not thrown');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('REQUIRED_FIELD_MISSING'));
        }
        Test.stopTest();
    }

    @IsTest
    static void upsertRecords_nullInput_returnsEmpty() {
        Test.startTest();
        Database.UpsertResult[] results = DmlService.upsertRecords(null);
        Test.stopTest();

        Assert.areEqual(0, results.size());
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    // ── DELETE ───────────────────────────────────────────────────────────────

    @IsTest
    static void deleteRecords_success_noLogs() {
        Account a = new Account(Name = 'To Delete');
        insert a;

        Test.startTest();
        Database.DeleteResult[] results = DmlService.deleteRecords(new List<Account>{ a });
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    @IsTest
    static void deleteRecords_partial_logsOneEntry() {
        Account real = new Account(Name = 'Real');
        insert real;

        Account ghost = new Account(Id = '001000000000000AAA');

        Test.startTest();
        Database.DeleteResult[] results = DmlService.deleteRecords(
            new List<Account>{ real, ghost }
        );
        Test.stopTest();

        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());

        List<Error_Log__c> logs = [SELECT Error_Count__c, Status__c FROM Error_Log__c WHERE Operation__c = 'DELETE'];
        Assert.areEqual(1, logs.size());
        Assert.areEqual(1, (Integer) logs[0].Error_Count__c);
        Assert.areEqual('Open', logs[0].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :logs[0].Id]);
    }

    @IsTest
    static void deleteRecords_allOrNone_propagatesException() {
        Account ghost = new Account(Id = '001000000000000AAA');

        Test.startTest();
        try {
            DmlService.deleteRecords(new List<Account>{ ghost }, true);
            Assert.fail('Expected DmlException not thrown');
        } catch (DmlException e) {
            Assert.isTrue(
                e.getMessage().contains('ENTITY_IS_DELETED') ||
                e.getMessage().contains('INVALID_CROSS_REFERENCE_KEY') ||
                e.getMessage().contains('NOT_FOUND') ||
                e.getNumDml() > 0,
                'Expected a DML error for non-existent record, got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void deleteRecords_nullInput_returnsEmpty() {
        Test.startTest();
        Database.DeleteResult[] results = DmlService.deleteRecords(null);
        Test.stopTest();

        Assert.areEqual(0, results.size());
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c]);
    }

    // ── clearRecentLogIds ─────────────────────────────────────────────────────

    @IsTest
    static void clearRecentLogIds_clearsAccumulatedIds() {
        Account bad = new Account();

        DmlService.clearRecentLogIds();

        Test.startTest();
        DmlService.insertRecords(new List<Account>{ bad });
        Test.stopTest();

        Assert.areEqual(1, DmlService.recentLogIds.size(), 'Expected one log id after a failed insert');

        DmlService.clearRecentLogIds();
        Assert.areEqual(0, DmlService.recentLogIds.size(), 'Expected empty list after clear');
    }
}
