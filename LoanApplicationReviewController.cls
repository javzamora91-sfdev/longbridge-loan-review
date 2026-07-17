/*------------
/@Author: Adrian Vega
/@Version: V6
/@Date: 07/17/2026
/@Purpose: Class to handle LWC connection and updates for Loan Application, bypassing cacheable constraints.
/@Test Class: LoanApplicationReviewController_TEST
/------------ */

public with sharing class LoanApplicationReviewController {
    @AuraEnabled
    public static List<Loan_Application__c> getLoanApplications(String status) {
        return [
            SELECT Id, Name, Applicant_Account__r.Name, Primary_Applicant__r.Name, 
                   Product__c, Loan_Amount__c, Status__c, Decision_Reason__c
            FROM Loan_Application__c
            WHERE Status__c = :status
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 100
        ];
    }

    public class DecisionWrapper {
        @AuraEnabled public Id loanId { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String decisionReason { get; set; }
    }

    @AuraEnabled
    public static void processDecision(List<DecisionWrapper> decisions) {
        if (decisions == null || decisions.isEmpty()) {
            return;
        }

        List<Loan_Application__c> loansToUpdate = new List<Loan_Application__c>();

        for (DecisionWrapper dw : decisions) {
            Loan_Application__c loan = new Loan_Application__c(
                Id = dw.loanId,
                Status__c = dw.status,
                Decision_Reason__c = dw.decisionReason
            );

            if (dw.status == 'Approved') {
                loan.Decision_Date__c = System.now();
            }

            loansToUpdate.add(loan);
        }

        try {
            update as user loansToUpdate;
        } catch (Exception e) {
            throw new AuraHandledException('Error processing decisions: ' + e.getMessage());
        }
    }
}