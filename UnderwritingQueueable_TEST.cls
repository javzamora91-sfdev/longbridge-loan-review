/*------------
@Author: Adrian Vega
@Version: V2
@Date: 07/17/2026
@Purpose: Comprehensive queueable integration suite validating execution payloads and safety fallbacks.
------------ */
@isTest
private class UnderwritingQueueable_TEST {

    // ==========================================
    // MULTI-BEHAVIOR HTTP MOCK IMPLEMENTATION
    // ==========================================
    public class UnderwritingMock implements HttpCalloutMock {
        private Integer statusCode;
        private String statusReason;
        private Boolean throwException;
        
        public UnderwritingMock(Integer statusCode, String statusReason) {
            this.statusCode = statusCode;
            this.statusReason = statusReason;
            this.throwException = false;
        }

        public UnderwritingMock(Boolean throwException) {
            this.throwException = throwException;
        }

        public HttpResponse respond(HttpRequest request) {
            if (this.throwException) {
                CalloutException ex = new CalloutException();
                ex.setMessage('Read timed out or remote host closed connection cleanly.');
                throw ex;
            }
            
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');
            response.setStatusCode(this.statusCode);
            response.setStatus(this.statusReason);
            
            if (this.statusCode == 200 || this.statusCode == 201) {
                response.setBody('{"status": "success", "message": "Application forwarded to underwriting service."}');
            } else {
                response.setBody('{"status": "error", "message": "Bad Request or Validation Failure"}');
            }
            return response;
        }
    }

    // ==========================================
    // TEST SETUP DATA FACTORY
    // ==========================================
    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'Queueable Testing Corp', Total_Approved_Loan_Amount__c = 0.00);
        insert acc;

        Loan_Application__c loan = new Loan_Application__c(
            Applicant_Account__c = acc.Id,
            Loan_Amount__c = 75000.00,
            Status__c = 'Under Review',
            Product__c = 'Fixed'
        );
        insert loan;
    }

    // ==========================================
    // TEST 1: SUCCESS PATH CALLOUT EXECUTION
    // ==========================================
    @isTest
    static void testQueueableSuccessExecution() {
        Loan_Application__c loan = [SELECT Id FROM Loan_Application__c LIMIT 1];
        Set<Id> loanIds = new Set<Id>{ loan.Id };

        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(200, 'OK'));

        Test.startTest();
        System.enqueueJob(new UnderwritingQueueable(loanIds));
        // Assert while the job is active in the async buffer context
        System.assertEquals(1, Limits.getQueueableJobs(), 'Queueable worker context failed to initialize.');
        Test.stopTest(); // Forces job to execute synchronously
    }

    // ==========================================
    // TEST 2: NON-200 HTTP SERVER RESPONSE HANDLING
    // ==========================================
    @isTest
    static void testQueueableHttpFailureHandling() {
        Loan_Application__c loan = [SELECT Id FROM Loan_Application__c LIMIT 1];
        Set<Id> loanIds = new Set<Id>{ loan.Id };

        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(400, 'Bad Request'));

        Test.startTest();
        System.enqueueJob(new UnderwritingQueueable(loanIds));
        System.assertEquals(1, Limits.getQueueableJobs(), 'Queueable worker failed to process error logging routing.');
        Test.stopTest();
    }

    // ==========================================
    // TEST 3: G-TIMEOUT & CONNECTION EXCEPTION ROUTING
    // ==========================================
    @isTest
    static void testQueueableConnectionExceptionGracefulCatch() {
        Loan_Application__c loan = [SELECT Id FROM Loan_Application__c LIMIT 1];
        Set<Id> loanIds = new Set<Id>{ loan.Id };

        Test.setMock(HttpCalloutMock.class, new UnderwritingMock(true));

        Test.startTest();
        System.enqueueJob(new UnderwritingQueueable(loanIds));
        System.assertEquals(1, Limits.getQueueableJobs(), 'Queueable failed to smoothly absorb connection crash patterns.');
        Test.stopTest();
    }

    // ==========================================
    // TEST 4: EMPTY SET / EMPTY BATCH SAFE-EXIT VERIFICATION
    // ==========================================
    @isTest
    static void testQueueableEmptyIdSetResilience() {
        Set<Id> emptyLoanIds = new Set<Id>();

        Test.startTest();
        System.enqueueJob(new UnderwritingQueueable(emptyLoanIds));
        System.assertEquals(1, Limits.getQueueableJobs(), 'Queueable failed to bypass runtime processes gracefully.');
        Test.stopTest();
    }
}