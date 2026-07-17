/*------------
/@Author: Adrian Vega
/@Version: V1
/@Date: 07/17/2026
/@Purpose: Asynchronous worker class handling REST API callouts to underwriting services safely.
/@Test Class: UnderwritingQueueable_TEST
/------------ */
public class UnderwritingQueueable implements System.Queueable, Database.AllowsCallouts {
    
    private Set<Id> loanIds;

    public UnderwritingQueueable(Set<Id> loanIds) {
        this.loanIds = loanIds;
    }

    public void execute(System.QueueableContext context) {
        List<Loan_Application__c> loans = [
            SELECT Id, Name, Loan_Amount__c, Status__c, Product__c, Applicant_Account__r.Name
            FROM Loan_Application__c
            WHERE Id IN :loanIds
            WITH USER_MODE
        ];

        for (Loan_Application__c loan : loans) {
            Http http = new Http();
            HttpRequest request = new HttpRequest();
            
            
            request.setEndpoint('callout:Underwriting_API_Named_Credential/v1/applications');
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            
            Map<String, Object> payload = new Map<String, Object>{
                'sfId' => loan.Id,
                'applicationNumber' => loan.Name,
                'amount' => loan.Loan_Amount__c,
                'product' => loan.Product__c,
                'accountName' => loan.Applicant_Account__r.Name
            };
            request.setBody(JSON.serialize(payload));

            try {
                HttpResponse response = http.send(request);
                
                if (response.getStatusCode() != 200 && response.getStatusCode() != 201) {
                    logFailure(loan.Id, 'HTTP_ERROR_' + response.getStatusCode(), response.getBody());
                }
            } catch (Exception ex) {
                // Captures failures for support
                logFailure(loan.Id, 'CONNECTION_EXCEPTION', ex.getMessage() + '\n' + ex.getStackTraceString());
            }
        }
    }

    private static void logFailure(Id recordId, String errorType, String details) {
        System.debug('INTEGRATION_FAILURE [' + errorType + '] on Record ' + recordId + ': ' + details);
        // set below this line an insert to the error log obj
        
    }
}