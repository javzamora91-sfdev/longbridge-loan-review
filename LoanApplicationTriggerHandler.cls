/*------------
/@Author: Adrian Vega
/@Version: V4
/@Date: 07/17/2026
/@Purpose: Trigger Handler for Loan Application to handle field updates and lookup rollup aggregations.
/@Test Class: LoanApplicationTriggerHandler_TEST
/------------ */
public with sharing class LoanApplicationTriggerHandler {
    public static void handleRollup(List<Loan_Application__c> newLoans, Map<Id, Loan_Application__c> oldLoans) {
        Set<Id> accountIdsToUpdate = new Set<Id>();
        
        // 1. Gather all affected Account IDs safely
        if (newLoans != null) {
            for (Loan_Application__c loan : newLoans) {
                if (loan.Applicant_Account__c != null) {
                    accountIdsToUpdate.add(loan.Applicant_Account__c);
                }
                if (oldLoans != null && oldLoans.containsKey(loan.Id) && oldLoans.get(loan.Id).Applicant_Account__c != null) {
                    accountIdsToUpdate.add(oldLoans.get(loan.Id).Applicant_Account__c);
                }
            }
        } else if (oldLoans != null) {
            for (Loan_Application__c oldLoan : oldLoans.values()) {
                if (oldLoan.Applicant_Account__c != null) {
                    accountIdsToUpdate.add(oldLoan.Applicant_Account__c);
                }
            }
        }

        // 2. Fire the calculation engine
        if (!accountIdsToUpdate.isEmpty()) {
            calculateAccountTotals(accountIdsToUpdate, newLoans);
        }
    }

    private static void calculateAccountTotals(Set<Id> accountIds, List<Loan_Application__c> triggerNew) {
        Map<Id, Account> accountsToUpdateMap = new Map<Id, Account>();
        Map<Id, Loan_Application__c> activeTriggerMap = new Map<Id, Loan_Application__c>();

        if (triggerNew != null) {
            for (Loan_Application__c lan : triggerNew) {
                activeTriggerMap.put(lan.Id, lan);
            }
        }

        for (Id accId : accountIds) {
            accountsToUpdateMap.put(accId, new Account(Id = accId, Total_Approved_Loan_Amount__c = 0.00));
        }

        List<Loan_Application__c> allLoans = [
            SELECT Id, Applicant_Account__c, Loan_Amount__c, Status__c 
            FROM Loan_Application__c 
            WHERE Applicant_Account__c IN :accountIds
            WITH USER_MODE
        ];

        for (Loan_Application__c loan : allLoans) {
            String status = loan.Status__c;
            Decimal amount = loan.Loan_Amount__c;

            if (activeTriggerMap.containsKey(loan.Id)) {
                status = activeTriggerMap.get(loan.Id).Status__c;
                // If amount is missing from LWC payload, retain the database value
                if (activeTriggerMap.get(loan.Id).Loan_Amount__c != null) {
                    amount = activeTriggerMap.get(loan.Id).Loan_Amount__c;
                }
            }

            if (status == 'Approved' && amount != null) {
                Id accId = loan.Applicant_Account__c;
                if (accountsToUpdateMap.containsKey(accId)) {
                    accountsToUpdateMap.get(accId).Total_Approved_Loan_Amount__c += amount;
                }
            }
        }

        if (!accountsToUpdateMap.isEmpty()) {
            try {
                update as system accountsToUpdateMap.values();
            } catch (Exception e) {
                System.debug('Error rolling up Loan Application totals: ' + e.getMessage());
            }
        }
    }

    public static void handleAfterUpdate(List<Loan_Application__c> newLoans, Map<Id, Loan_Application__c> oldLoans) {
    Set<Id> loansToNotify = new Set<Id>();

    for (Loan_Application__c loan : newLoans) {
        Loan_Application__c oldLoan = oldLoans.get(loan.Id);
        if (loan.Status__c == 'Approved' && oldLoan.Status__c != 'Approved') {
            loansToNotify.add(loan.Id);
        }
    }

    if (!loansToNotify.isEmpty()) {
        System.enqueueJob(new UnderwritingQueueable(loansToNotify));
    }
}
}