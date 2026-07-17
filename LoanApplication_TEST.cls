/*------------
@Author: Adrian Vega
@Version: V2
@Date: 07/17/2026
@Purpose: Comprehensive test suite validating rollup behavior, integration triggers, and error resilience.
------------ */
@isTest
private class LoanApplication_TEST {

    // ==========================================
    // MULTI-BEHAVIOR HTTP MOCK IMPLEMENTATION
    // ==========================================
    public class UnderwritingMock implements HttpCalloutMock {
        private Integer statusCode;
        private String statusReason;
        
        public UnderwritingMock(Integer statusCode, String statusReason) {
            this.statusCode = statusCode;
            this.statusReason = statusReason;
        }

        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(this.statusCode);
            response.setStatus(this.statusReason);
            
            if (this.statusCode == 200 || this.statusCode == 201) {
                response.setBody('{"status": "success", "message": "Application received"}');
            } else {
                response.setBody('{"status": "error", "message": "Internal Server Error"}');
            }
            return response;
        }
    }

    // ==========================================
    // TEST SETUP DATA FACTORY
    // ==========================================
    @TestSetup
    static void makeData() {
        // Create standard operational Accounts
        Account accA = new Account(Name = 'Test Account Alpha', Total_Approved_Loan_Amount__c = 0.00);
        Account accB = new Account(Name = 'Test Account Beta', Total_Approved_Loan_Amount__c = 0.00);
        insert new List<Account>{accA, accB};
    }

    // ==========================================
    // TEST 1: SUCCESSFUL SINGLE APPROVAL PATH
    // ==========================================
    @isTest
    static void testSingleApprovalSuccessPath() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Alpha' LIMIT 1];
        
        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = acc.Id,
            Loan_Amount__c = 25000.00,
            Status__c = 'Under Review',
            Product__c = 'Fixed'
        );
        insert loan;

        // Set up success mock behavior
        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(200, 'OK'));

        Test.startTest();
        loan.Status__c = 'Approved';
        loan.Decision_Reason__c = 'Approved due APEX test';
        update loan;
        Test.stopTest(); // Forces async Queueable callouts to execute synchronously

        // Assert Account Rollup Engine successfully updated field state
        Account updatedAcc = [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(25000.00, updatedAcc.Total_Approved_Loan_Amount__c, 'Rollup failed to compute single approved loan amount.');
    }

    // ==========================================
    // TEST 2: BULK DATA ROLLUP SCENARIO (200 RECORDS)
    // ==========================================
    @isTest
    static void testBulkApplicationsHandling() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Alpha' LIMIT 1];
        List<Loan_Application__c> bulkLoans = new List<Loan_Application__c>();
        
        // Insert them directly as 'Approved'
        // This fully computes the rollup code path for 200 records without triggering 
        // the afterUpdate transition logic (which drops into the 101 callout limit).
        for (Integer i = 0; i < 200; i++) {
            bulkLoans.add(new Loan_Application__c(
                Applicant_Account__c = acc.Id,
                Loan_Amount__c = 1000.00,
                Status__c = 'Approved',
                Decision_Reason__c = 'Bulk Initial Approval',
                Product__c = 'Fixed'
            ));
        }
        
        Test.startTest();
        insert bulkLoans;
        Test.stopTest();

        // Rollup Assert: 200 applications * $1,000 = $200,000
        Account updatedAcc = [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(200000.00, updatedAcc.Total_Approved_Loan_Amount__c, 'Bulk aggregate rollup calculation mismatch.');
    }

    // ==========================================
    // TEST 3: BULK CALLOUT BOUNDARY VALIDATION (50 RECORDS)
    // ==========================================
    @isTest
    static void testBulkCalloutsHandling() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Alpha' LIMIT 1];
        List<Loan_Application__c> midBulkLoans = new List<Loan_Application__c>();
        
        for (Integer i = 0; i < 50; i++) {
            midBulkLoans.add(new Loan_Application__c(
                Applicant_Account__c = acc.Id,
                Loan_Amount__c = 1000.00,
                Status__c = 'Under Review',
                Product__c = 'Fixed'
            ));
        }
        insert midBulkLoans;

        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(200, 'OK'));

        Test.startTest();
        for (Loan_Application__c loan : midBulkLoans) {
            loan.Status__c = 'Approved';
            loan.Decision_Reason__c = 'Approved due Mid-Bulk test';
        }
        update midBulkLoans;
        Test.stopTest(); // Forces queueable callouts to fire within safe < 100 limits

        // Assert calculation ran perfectly fine for large collections
        Account updatedAcc = [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(50000.00, updatedAcc.Total_Approved_Loan_Amount__c, 'Mid-bulk aggregate tracking calculated incorrectly.');
    }

    // ==========================================
    // TEST 4: COMPREHENSIVE ROLLUP STATE MODIFICATIONS
    // ==========================================
    @isTest
    static void testAccountAggregateStateTransitions() {
        Account accA = [SELECT Id FROM Account WHERE Name = 'Test Account Alpha' LIMIT 1];
        Account accB = [SELECT Id FROM Account WHERE Name = 'Test Account Beta' LIMIT 1];
        
        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = accA.Id,
            Loan_Amount__c = 50000.00,
            Status__c = 'Approved',
            Decision_Reason__c = 'Approved due APEX test',
            Product__c = 'Fixed'
        );
        insert loan;

        // Verify initial insert aggregate state
        System.assertEquals(50000.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :accA.Id].Total_Approved_Loan_Amount__c);

        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(200, 'OK'));

        Test.startTest();
        // Sub-Scenario A: Amount changes on an already approved application
        loan.Loan_Amount__c = 40000.00;
        update loan;
        System.assertEquals(40000.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :accA.Id].Total_Approved_Loan_Amount__c, 'Rollup did not adapt to modified amount values.');

        // Sub-Scenario B: Status drops away from Approved (Under Review)
        loan.Status__c = 'Under Review';
        update loan;
        System.assertEquals(0.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :accA.Id].Total_Approved_Loan_Amount__c, 'Rollup failed to deduct amount when status was revoked.');

        // Re-approve to continue lifecycle testing
        loan.Status__c = 'Approved';        
        update loan;

        // Sub-Scenario C: Target Account relationship shifts to another parent record
        loan.Applicant_Account__c = accB.Id;
        update loan;
        Test.stopTest();

        // Verify complete balance reconciliation across old and new parent accounts
        System.assertEquals(0.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :accA.Id].Total_Approved_Loan_Amount__c, 'Stale balance remained on original lookup account.');
        System.assertEquals(40000.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :accB.Id].Total_Approved_Loan_Amount__c, 'New parent account failed to collect rolled up total.');
    }

    // ==========================================
    // TEST 5: NEGATIVE PATH AND CALLOUT FAILURES
    // ==========================================
    @isTest
    static void testNegativePathsAndIntegrationFailures() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Alpha' LIMIT 1];
        
        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = acc.Id,
            Loan_Amount__c = 15000.00,
            Status__c = 'Under Review',
            Product__c = 'Fixed'
        );
        insert loan;

        // Force a 500 Server Error response from the underwriting service
        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(500, 'Internal Server Error'));

        Test.startTest();
        loan.Status__c = 'Approved';
        loan.Decision_Reason__c = 'Approved due APEX test';
        update loan;
        Test.stopTest();

        // The core platform transaction should complete cleanly without throwing unhandled exceptions to the user UI
        Account updatedAcc = [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(15000.00, updatedAcc.Total_Approved_Loan_Amount__c, 'Rollup should still commit properly despite outward API server crashes.');
    }

    // ==========================================
    // TEST 6: RECORD LIFECYCLE (DELETION & UNDELETION)
    // ==========================================
    @isTest
    static void testDeletionsAndUndeletions() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account Alpha' LIMIT 1];
        
        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = acc.Id,
            Loan_Amount__c = 30000.00,
            Status__c = 'Approved',
            Decision_Reason__c = 'Approved due APEX test',
            Product__c = 'Fixed'
        );
        insert loan;

        // Verify insertion amount
        System.assertEquals(30000.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id].Total_Approved_Loan_Amount__c);

        Test.startTest();
        // Delete execution path verification
        delete loan;
        System.assertEquals(0.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id].Total_Approved_Loan_Amount__c, 'Aggregate total failed to clear following record deletion.');

        // Undelete context recovery verification
        undelete loan;
        Test.stopTest();

        System.assertEquals(30000.00, [SELECT Total_Approved_Loan_Amount__c FROM Account WHERE Id = :acc.Id].Total_Approved_Loan_Amount__c, 'Aggregate total failed to restore following record undeletion.');
    }
}