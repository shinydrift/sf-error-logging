# sf-error-logging

Salesforce DX project providing a centralised DML utility with automatic error logging.

## What's in here

### `DmlService`

A static Apex utility that wraps `Database.*` operations and persists record-level failures to `Error_Log__c` in the same transaction.

**Default behaviour:** partial success (`allOrNone=false`) — successful records commit even when others fail.
**Override:** pass `allOrNone=true` to any method to get all-or-nothing semantics. Note that with `allOrNone=true`, a `DmlException` is thrown on failure and no error log is written (the exception fires before results are returned).

#### Usage

```apex
// Insert — partial by default
Database.SaveResult[] results = DmlService.insertRecords(accounts);

// Insert — all or nothing
Database.SaveResult[] results = DmlService.insertRecords(accounts, true);

// Update
Database.SaveResult[] results = DmlService.updateRecords(contacts);

// Upsert
Database.UpsertResult[] results = DmlService.upsertRecords(cases);

// Delete
Database.DeleteResult[] results = DmlService.deleteRecords(oldRecords);
```

All methods return the standard `Database.*Result[]` array so callers can inspect individual results as normal.

#### Supported operations

| Method | Return type |
|---|---|
| `insertRecords(records)` | `Database.SaveResult[]` |
| `insertRecords(records, allOrNone)` | `Database.SaveResult[]` |
| `updateRecords(records)` | `Database.SaveResult[]` |
| `updateRecords(records, allOrNone)` | `Database.SaveResult[]` |
| `upsertRecords(records)` | `Database.UpsertResult[]` |
| `upsertRecords(records, allOrNone)` | `Database.UpsertResult[]` |
| `deleteRecords(records)` | `Database.DeleteResult[]` |
| `deleteRecords(records, allOrNone)` | `Database.DeleteResult[]` |

---

### `Error_Log__c`

Custom object that stores one record per DML failure.

| Field | Type | Description |
|---|---|---|
| `Name` | AutoNumber (EL-00000) | Unique identifier |
| `Object_Type__c` | Text(255) | SObject API name |
| `Operation__c` | Picklist | INSERT / UPDATE / UPSERT / DELETE |
| `Record_Id__c` | Text(18) | ID of the failed record (null for failed inserts) |
| `Error_Message__c` | LongTextArea | Error message(s) joined by newline |
| `Status_Code__c` | Text(255) | Salesforce status code(s) (e.g. REQUIRED_FIELD_MISSING) |
| `Fields__c` | LongTextArea | Field names flagged by the error |

---

## Deployment

Deploy `Error_Log__c` and `DmlService` together:

```bash
sf project deploy start --source-dir force-app
```

The object must exist in the org before `DmlService` is usable.

## Tests

```bash
sf apex run test --class-names DmlServiceTest --result-format human
```

12 test methods covering happy path, partial failure, `allOrNone` propagation, and null input for all four operations.

## Known gaps / backlog

These were flagged in code review and are candidates for a follow-up:

- `Error_Log__c` does not capture caller context (user ID, stack trace, transaction ID) — useful for production debugging
- `allOrNone=true` failures are not logged — DmlException propagates before log methods run
- `without sharing` on `DmlService` bypasses sharing rules on business DML, not just log writes — should be split into `inherited sharing` outer class + `without sharing` inner log writer
- No `Database.DMLOptions` or external-ID upsert overload
- Logs created in the same transaction are rolled back if the transaction fails after the DML — consider Platform Events for durable logging
