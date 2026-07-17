/*------------
@Author: Adrian Vega
@Version: V2
@Date: 07/17/2026
@Purpose: Service-layer test suite validating the handler logic with database-backed query support.
------------ */
@isTest
private class LoanApplicationTriggerHandler_TEST {

    public class UnderwritingMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(200);
            response.setStatus('OK');
            response.setBody('{"status":"success"}');
            return response;
        }
    }

    @TestSetup
    static void makeData() {
        Account accA = new Account(Name = 'Handler Alpha Account', Total_Approved_Loan_Amount__c = 0.00);
        Account accB = new Account(Name = 'Handler Beta Account', Total_Approved_Loan_Amount__c = 0.00);
        insert new List<Account>{accA, accB};
    }

    // ==========================================
    // TEST 1: DIRECT ROLLUP VALIDATION (INSERT)
    // ==========================================
    @isTest
    static void testHandleRollupOnInsertContext() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Handler Alpha Account' LIMIT 1];
        
        // Insert record to DB so the handler's internal SOQL query can locate it
        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = acc.Id,
            Loan_Amount__c = 15000.00,
            Status__c = 'Approved',
            Product__c = 'Fixed',
            Decision_Reason__c = 'Approved due APEX test'
        );
        insert loan;

        List<Loan_Application__c> newLoans = new List<Loan_Application__c>{ loan };

        Test.startTest();
        // Invoke method directly to test the handler logic isolation
        LoanApplicationTriggerHandler.handleRollup(newLoans, null);
        Test.stopTest();

        Account updatedAcc = [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(15000.00, updatedAcc.Total_Approved_Loan_Amount__c, 'Direct insert context rollup computation failed.');
    }

    // ==========================================
    // TEST 2: DIRECT ROLLUP VALIDATION (DELETE)
    // ==========================================
    @isTest
    static void testHandleRollupOnDeleteContext() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Handler Alpha Account' LIMIT 1];

        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = acc.Id,
            Loan_Amount__c = 20000.00,
            Status__c = 'Approved',
            Product__c = 'Fixed',
            Decision_Reason__c = 'Approved due APEX test'
        );
        insert loan;
        
        // Capture the state before deleting the record from the database context
        Map<Id, Loan_Application__c> oldLoans = new Map<Id, Loan_Application__c>{ loan.Id => loan };
        delete loan; 

        Test.startTest();
        LoanApplicationTriggerHandler.handleRollup(null, oldLoans);
        Test.stopTest();

        // Since the record was deleted from the DB, the handler's query returns nothing, 
        // resetting the account back cleanly to 0.00.
        Account updatedAcc = [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(0.00, updatedAcc.Total_Approved_Loan_Amount__c, 'Direct delete context rollup clearance failed.');
    }

    // ==========================================
    // TEST 3: INTEGRATION STATE FILTER & IDEMPOTENCY
    // ==========================================
    @isTest
    static void testHandleAfterUpdateNotificationFilter() {
        Id loanIdA = fakedId(Loan_Application__c.SObjectType, 1);
        Id loanIdB = fakedId(Loan_Application__c.SObjectType, 2);

        Loan_Application__c newLoanA = new Loan_Application__c(Id = loanIdA, Status__c = 'Approved');
        Loan_Application__c oldLoanA = new Loan_Application__c(Id = loanIdA, Status__c = 'Under Review');

        Loan_Application__c newLoanB = new Loan_Application__c(Id = loanIdB, Status__c = 'Approved', Loan_Amount__c = 50000);
        Loan_Application__c oldLoanB = new Loan_Application__c(Id = loanIdB, Status__c = 'Approved', Loan_Amount__c = 40000);

        List<Loan_Application__c> newLoansList = new List<Loan_Application__c>{newLoanA, newLoanB};
        Map<Id, Loan_Application__c> oldLoansMap = new Map<Id, Loan_Application__c>{
            loanIdA => oldLoanA,
            loanIdB => oldLoanB
        };

        Test.setMock(HttpCalloutMock.class, new UnderwritingMock());

        Test.startTest();
        LoanApplicationTriggerHandler.handleAfterUpdate(newLoansList, oldLoansMap);
        System.assertEquals(1, Limits.getQueueableJobs(), 'Idempotency validation failed: unexpected queueable count.');
        Test.stopTest();
    }

    // ==========================================
    // TEST 4: NEGATIVE PATH / NULL PARAMETER RESILIENCE
    // ==========================================
    @isTest
    static void testNullParameterResilience() {
        Test.startTest();
        try {
            LoanApplicationTriggerHandler.handleRollup(null, null);
            LoanApplicationTriggerHandler.handleAfterUpdate(new List<Loan_Application__c>(), new Map<Id, Loan_Application__c>());
            System.assert(true);
        } catch (Exception ex) {
            System.assert(false, 'Method parameter validation threw unhandled exceptions: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    private static Id fakedId(Schema.SObjectType sobjectType, Integer recordCount) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        String fakeIdSuffix = String.valueOf(recordCount).leftPad(12, '0');
        return Id.valueOf(keyPrefix + fakeIdSuffix);
    }
}