/*------------
@Author: Joel Adrian Vega
@Version: V8
@Date: 07/17/2026
@Purpose: Database trigger routing execution contexts to the handler class.
@Test Class: LoanApplication_TEST     
------------ */
trigger LoanApplication on Loan_Application__c (after insert, after update, after delete, after undelete) {

    if (Trigger.isAfter) {
        if (Trigger.isUpdate) {
            LoanApplicationTriggerHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
        LoanApplicationTriggerHandler.handleRollup(Trigger.new, Trigger.oldMap);
    }
}