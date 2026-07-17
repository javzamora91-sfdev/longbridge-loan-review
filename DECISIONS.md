```markdown
# Architectural & Automation Decisions
**Author:** Adrian Vega
**Date:** July 17, 2026

This document details the trade-offs and structural choices made during this implementation, choosing between declarative automation and programmatic code.

---

1. Stamping and Protecting Decisions

Choice: Before-Save Flow (Stamping) + Apex Trigger Handler
*   **Alternative Considered:** Handling both stamping and protection entirely within an Apex After-Update Trigger block.
*   **Reasoning:** 
    1. **Stamping:** A Before-Save Flow was chosen to update the `Decision_Date__c` field because it runs significantly faster than Apex After-Save triggers and eliminates unnecessary extra DML database roundtrips.
    2. **Protection:** While the Flow stamps the date, the programmatic conditional blocks are also used to enforce the Decision_Date__c stamping securely via Apex. This creates a clean separation of concerns: low-overhead decoration happens in Flow, while transactional structural enforcement happens in code.

---

2. Maintaining the Applicant Total Account Rollup

Choice: Service-Layer Apex Architecture (Trigger Handler)
*   **Alternative Considered:** Declarative Record-Triggered Flow or Rollup Summary Field.
*   **Reasoning:** Since `Loan_Application__c` is tied to `Account` via a flexible **Lookup** rather than a Master-Detail relationship (and this one was not selected due the risk of loosing financial data if an account is deleted or merged), standard declarative Rollup Summary Fields are not supported. While Record-Triggered Flows can loop over structures, they become sluggish and risk hitting governor limits under 200-record bulk data loads. The Apex implementation collects target account IDs into a `Set` and computes values via an aggregated, loop-free SOQL query. This keeps the transaction safe for bulk actions, undeletes, and lookup changes.

---

3. Underwriting System Notifications & Integration

Choice: Transaction-Isolated Queueable Apex (`System.Queueable` + `AllowsCallouts`)
*   **Alternative Considered:** Future Methods (`@future(callout=true)`) or Salesforce Outbound Messaging.
*   **Reasoning:** Future methods do not support complex object arrays or object parameter states cleanly. Outbound Messaging lacks dynamic payload transformation capabilities. 
*   **Queueable advantages include:**
    1. Perfect asynchronous isolation away from the foreground save operation.
    2. Allows structured payload generation via serialized Maps (`JSON.serialize`).
    3. Better error handling through standard `try-catch` blocks that catch connection drops or timeouts without failing the parent transaction.

---


4. Production Scaling & Idempotency Strategy
*   **Current State Failures:** Network timeouts are caught safely and passed to a `logFailure` debug method.
*   **Production Enhancement Pattern:** For high-volume production deployments, the `logFailure` method should insert records into a custom `Integration_Error_Log__c` object. A scheduled batch job or an event-driven framework (like Salesforce Platform Events) can then pick up failed records for automated retry handling, keeping everything tracking correctly within limits.
