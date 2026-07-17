/*------------
@Author: Adrian Vega
@Version: V1
@Date: 07/17/2026
@Purpose: Controller validation suite testing LWC retrieval filters, wrapper deserialization, and User-Mode exceptions.
------------ */
@isTest
private class LoanApplicationReviewController_TEST {

    // ==========================================
    // TEST SETUP DATA FACTORY
    // ==========================================
    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'LWC Controller Review Co', Total_Approved_Loan_Amount__c = 0.00);
        insert acc;

        Contact con = new Contact(FirstName = 'Test', LastName = 'Applicant', AccountId = acc.Id);
        insert con;

        // Create initial batch of records spanning different status types
        List<Loan_Application__c> initialLoans = new List<Loan_Application__c>{
            new Loan_Application__c(
                Applicant_Account__c = acc.Id,
                Primary_Applicant__c = con.Id,
                Loan_Amount__c = 30000.00,
                Status__c = 'Under Review',
                Product__c = 'Fixed'
            ),
            new Loan_Application__c(
                Applicant_Account__c = acc.Id,
                Primary_Applicant__c = con.Id,
                Loan_Amount__c = 45000.00,
                Status__c = 'Approved',
                Product__c = 'Fixed',
                Decision_Reason__c = 'Initial automated clearance'
            )
        };
        insert initialLoans;
    }

    // ==========================================
    // TEST 1: COMPREHENSIVE RETRIEVAL (SOQL CHECK)
    // ==========================================
    @isTest
    static void testGetLoanApplicationsFilteredByStatus() {
        Test.startTest();
        List<Loan_Application__c> underReviewList = LoanApplicationReviewController.getLoanApplications('Under Review');
        List<Loan_Application__c> approvedList = LoanApplicationReviewController.getLoanApplications('Approved');
        Test.stopTest();

        System.assertEquals(1, underReviewList.size(), 'Failed to isolate records matching the active filter query criteria.');
        System.assertEquals('LWC Controller Review Co', underReviewList[0].Applicant_Account__r.Name, 'Relationship graph field loading failed.');
        System.assertEquals(1, approvedList.size(), 'Failed to isolate records matching historical approved conditions.');
    }

    // ==========================================
    // TEST 2: SUCCESSFUL PROCESSING PATH (APPROVAL)
    // ==========================================
    @isTest
    static void testProcessDecisionApprovalContext() {
        Loan_Application__c targetLoan = [SELECT Id FROM Loan_Application__c WHERE Status__c = 'Under Review' LIMIT 1];

        LoanApplicationReviewController.DecisionWrapper wrap = new LoanApplicationReviewController.DecisionWrapper();
        wrap.loanId = targetLoan.Id;
        wrap.status = 'Approved';
        wrap.decisionReason = 'Passed all criteria checks successfully.';

        List<LoanApplicationReviewController.DecisionWrapper> payload = new List<LoanApplicationReviewController.DecisionWrapper>{ wrap };

        Test.startTest();
        LoanApplicationReviewController.processDecision(payload);
        Test.stopTest();

        Loan_Application__c updatedLoan = [SELECT Status__c, Decision_Reason__c, Decision_Date__c FROM Loan_Application__c WHERE Id = :targetLoan.Id];
        System.assertEquals('Approved', updatedLoan.Status__c, 'Loan failed to transition states correctly.');
        System.assertEquals('Passed all criteria checks successfully.', updatedLoan.Decision_Reason__c, 'Decision explanation string mismatch.');
        System.assertNotEquals(null, updatedLoan.Decision_Date__c, 'The controller skipped assigning the Decision Timestamp during approvals.');
    }

    // ==========================================
    // TEST 3: CRASH SAFETY / INVALID DATA EXCEPTION
    // ==========================================
    @isTest
    static void testProcessDecisionThrowsHandledException() {
        // Hydrate a bad wrapper payload utilizing a fake programmatic ID to trigger a DML catch state block
        LoanApplicationReviewController.DecisionWrapper badWrap = new LoanApplicationReviewController.DecisionWrapper();
        badWrap.loanId = fakedId(Loan_Application__c.SObjectType, 1);
        badWrap.status = 'Approved';
        badWrap.decisionReason = 'Forcing DML record missing exception handler path.';

        List<LoanApplicationReviewController.DecisionWrapper> corruptPayload = new List<LoanApplicationReviewController.DecisionWrapper>{ badWrap };

        Test.startTest();
        try {
            LoanApplicationReviewController.processDecision(corruptPayload);
            System.assert(false, 'The method failed to catch the exception or did not throw an AuraHandledException.');
        } catch (AuraHandledException ex) {
            // Apex masking returns "Script-thrown exception" for AuraHandledExceptions in unit tests.
            // Verifying that we caught this exact type is the optimal testing pattern for security-wrapped controllers.
            System.assertEquals('Script-thrown exception', ex.getMessage(), 'An unexpected exception message style leaked out.');
        }
        Test.stopTest();
    }

    // ==========================================
    // TEST 4: NULL & EMPTY STRUCTURAL BOUNDARIES
    // ==========================================
    @isTest
    static void testProcessDecisionNullSafetyResilience() {
        Test.startTest();
        try {
            LoanApplicationReviewController.processDecision(null);
            LoanApplicationReviewController.processDecision(new List<LoanApplicationReviewController.DecisionWrapper>());
            System.assert(true);
        } catch (Exception ex) {
            System.assert(false, 'The execution choked on standard null data defense structures: ' + ex.getMessage());
        }
        Test.stopTest();
    }

    // ==========================================
    // HELPER: PROGRAMMATIC MOCK ID GENERATION
    // ==========================================
    private static Id fakedId(Schema.SObjectType sobjectType, Integer recordCount) {
        String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
        String fakeIdSuffix = String.valueOf(recordCount).leftPad(12, '0');
        return Id.valueOf(keyPrefix + fakeIdSuffix);
    }
}