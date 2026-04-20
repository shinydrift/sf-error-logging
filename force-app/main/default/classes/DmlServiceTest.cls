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

        Test.startTest();
        Database.SaveResult[] results = DmlService.insertRecords(
            new List<Account>{ good, bad }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.isTrue(results[0].isSuccess());
        Assert.isFalse(results[1].isSuccess());

        List<Error_Log__c> logs = [
            SELECT Operation__c, Object_Type__c, Error_Count__c, Status__c
            FROM Error_Log__c
        ];
        Assert.areEqual(1, logs.size(), 'Expected one log entry per method call');
        Assert.areEqual('INSERT', logs[0].Operation__c);
        Assert.areEqual('Account', logs[0].Object_Type__c);
        Assert.areEqual(1, (Integer) logs[0].Error_Count__c);
        Assert.areEqual('Open', logs[0].Status__c);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :logs[0].Id]);
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
            Assert.isNotNull(e.getMessage());
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
            Assert.isNotNull(e.getMessage());
        }
        Test.stopTest();
    }
}
