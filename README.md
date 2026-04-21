# sf-error-logging

Salesforce DX project providing a centralised DML utility with automatic error logging and retry support.

## What's in here

### `DmlService`

A static Apex utility that wraps `Database.*` operations and persists record-level failures to a single `Error_Log__c` per method call. The full error payload (failed records + error details) is attached as a JSON file linked to the log.

**Default behaviour:** partial success (`allOrNone=false`) — successful records commit even when others fail.
**Override:** pass `allOrNone=true` to get all-or-nothing semantics. Note that with `allOrNone=true`, a `DmlException` is thrown on failure and no error log is written (the exception fires before results are returned).

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
| `insertRecords(records, options)` | `Database.SaveResult[]` |
| `updateRecords(records)` | `Database.SaveResult[]` |
| `updateRecords(records, allOrNone)` | `Database.SaveResult[]` |
| `updateRecords(records, options)` | `Database.SaveResult[]` |
| `upsertRecords(records)` | `Database.UpsertResult[]` |
| `upsertRecords(records, allOrNone)` | `Database.UpsertResult[]` |
| `upsertRecords(records, externalIdField)` | `Database.UpsertResult[]` |
| `upsertRecords(records, externalIdField, allOrNone)` | `Database.UpsertResult[]` |
| `deleteRecords(records)` | `Database.DeleteResult[]` |
| `deleteRecords(records, allOrNone)` | `Database.DeleteResult[]` |
| `clearRecentLogIds()` | `void` |

---

### `Error_Log__c`

Custom object — one record per `DmlService` method call that produced at least one failure.

| Field | Type | Description |
|---|---|---|
| `Name` | AutoNumber (EL-00000) | Unique identifier |
| `Object_Type__c` | Text(255) | SObject API name of the failed records |
| `Operation__c` | Picklist | INSERT / UPDATE / UPSERT / DELETE |
| `Error_Count__c` | Number | Count of records that failed in this call |
| `Running_User__c` | Text(255) | Username of the user who triggered the DML |
| `Stack_Trace__c` | LongTextArea | Apex stack trace at the point of failure |
| `Transaction_Id__c` | Text(255) | Salesforce request/transaction ID |
| `Status_Code__c` | Text(255) | First error status code from the failed records |
| `Status__c` | Picklist | Open / Retry / Resolved / Failed |
| `Parent_Log__c` | Lookup(Error_Log__c) | Links a retry's child log back to the original |

#### JSON payload attachment

For each log record, `DmlService` serialises the failed `SObject` records and their error details (messages, status codes, fields) as a JSON file (`error_payload.json`) and attaches it via `ContentVersion` / `ContentDocumentLink`. This keeps the `Error_Log__c` record lightweight while preserving the full context needed for investigation or retry.

---

### Retry support

Set `Status__c = 'Retry'` on any `Error_Log__c` record to trigger an automatic re-run of the original DML operation.

**How it works:**

1. `ErrorLogTrigger` (after-update) detects the `Open → Retry` transition and calls `ErrorLogRetryHandler.handleRetry()` synchronously in the same transaction.
2. `ErrorLogRetryHandler` reads the attached JSON payload, deserialises the failed records, and re-runs the original operation through `DmlService`.
3. The log status is updated:
   - All records succeed → `Resolved`
   - Any record fails → `Failed` (new failures produce their own `Error_Log__c` records linked back via `Parent_Log__c`)

---

## Deployment

Deploy `Error_Log__c`, `DmlService`, `ErrorLogRetryHandler`, and `ErrorLogTrigger` together:

```bash
sf project deploy start --source-dir force-app
```

The object must exist in the org before the Apex classes and trigger are usable.

## Docker / local development

The repo ships a Dockerfile with the Salesforce CLI pre-installed. Build and authenticate:

```bash
docker build -t sf-error-logging .
sf org login sfdx-url -f <(echo "$SFDX_AUTH_URL") -a target-org -s
```

## Tests

```bash
sf apex run test --class-names DmlServiceTest,ErrorLogRetryHandlerTest --result-format human
```

- `DmlServiceTest` — happy path, partial failure, `allOrNone` propagation, `DMLOptions` overloads, external-ID upsert, `recentLogIds` population, and null input for all operations
- `ErrorLogRetryHandlerTest` — retry lifecycle: `Resolved` on full success, `Failed` on continued failure, `Parent_Log__c` linking, missing-payload guard

## Known gaps / backlog

- `allOrNone=true` failures are not logged — `DmlException` propagates before log methods run
- Logs created in the same transaction are rolled back if the transaction fails after the DML — consider Platform Events for durable logging
