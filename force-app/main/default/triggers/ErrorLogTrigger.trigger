trigger ErrorLogTrigger on Error_Log__c (after update) {
    for (Error_Log__c log : Trigger.new) {
        Error_Log__c old = Trigger.oldMap.get(log.Id);
        if (log.Status__c == 'Retry' && old.Status__c != 'Retry') {
            if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
                System.enqueueJob(new DmlRetryQueueable(log.Id));
            } else {
                System.debug(LoggingLevel.WARN, 'ErrorLogTrigger: queueable limit reached, retry skipped for ' + log.Id);
            }
        }
    }
}
