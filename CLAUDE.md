# CLAUDE.md — sf-error-logging

Project context and conventions for AI-assisted development on this repo.

## Project purpose

Salesforce DX project providing a reusable DML utility (`DmlService`) that wraps `Database.*` operations with automatic error logging to a custom `Error_Log__c` object.

## Key files

| Path | Purpose |
|---|---|
| `force-app/main/default/classes/DmlService.cls` | Main utility class |
| `force-app/main/default/classes/DmlServiceTest.cls` | Test coverage |
| `force-app/main/default/objects/Error_Log__c/` | Custom object + field metadata |
| `sfdx-project.json` | SFDX project config (API version 62.0) |

## Conventions

- **DML always goes through `DmlService`** — never use raw `insert`/`update`/`delete` statements or bare `Database.*` calls in new code. This ensures failures are always logged.
- **Partial success by default** — `allOrNone=false` is the standard. Only use `allOrNone=true` explicitly when all-or-nothing semantics are required, and document why.
- **Operation string constants** — use the private `OP_*` constants (`OP_INSERT`, `OP_UPDATE`, `OP_UPSERT`, `OP_DELETE`). Never use raw string literals for operations.
- **No DML inside `DmlServiceTest`** for setup — use `insert` directly in test setup only (not via `DmlService`) to keep test data setup clean and fast.
- **API version:** 62.0 throughout. Keep `cls-meta.xml` and `field-meta.xml` files at `62.0`.

## Architecture decisions

### `without sharing` — known issue
`DmlService` is currently declared `without sharing`, which unintentionally bypasses sharing rules on all business DML, not just the log write. The intended fix (not yet applied) is:
- Outer class: `inherited sharing`
- Inner `LogWriter` class: `without sharing` (scoped only to `Error_Log__c` insert)

Do not widen the `without sharing` scope further until this is resolved.

### Same-transaction logging
`Error_Log__c` records are inserted in the same transaction as the failed business DML. This means logs are rolled back if the overall transaction fails later. This is a known trade-off — the alternative (Platform Events, Queueable Finalizer) is on the backlog.

### `allOrNone=true` does not log
When `allOrNone=true`, Salesforce throws `DmlException` before returning results, so `logSaveFailures` never runs. Callers using `allOrNone=true` must handle the exception themselves and should not expect `Error_Log__c` records to be created.

## Backlog items (from council review)

1. Split `without sharing` — `inherited sharing` outer, `without sharing` inner `LogWriter`
2. Add `Running_User__c`, `Stack_Trace__c`, `Transaction_Id__c` to `Error_Log__c`
3. Truncate `Status_Code__c` to 255 chars before assignment
4. Inspect `persistLogs` `SaveResult[]` and emit `System.debug(LoggingLevel.ERROR, ...)` on log failures
5. `upsertRecords` overload accepting `Schema.SObjectField externalIdField`
6. `Database.DMLOptions` support
7. Platform Event fallback for durable error logging

## Running tests

```bash
sf apex run test --class-names DmlServiceTest --result-format human
```

## Deploying

```bash
sf project deploy start --source-dir force-app
```

Deploy `Error_Log__c` metadata and `DmlService` together — the object must exist before the class runs.
