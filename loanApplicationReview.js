import { LightningElement, wire, track } from 'lwc';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOAN_OBJECT from '@salesforce/schema/Loan_Application__c';
import STATUS_FIELD from '@salesforce/schema/Loan_Application__c.Status__c';
import getLoanApplications from '@salesforce/apex/LoanApplicationReviewController.getLoanApplications';
import processDecision from '@salesforce/apex/LoanApplicationReviewController.processDecision';

export default class LoanApplicationReview extends LightningElement {
    @track statusFilter = 'New';
    @track applications = [];
    @track statusOptions = [];
    @track error;
    @track isLoading = false;

    @track isModalOpen = false;
    @track selectedLoanIds = [];
    @track decisionStatus = '';
    @track decisionReason = '';

    @wire(getObjectInfo, { objectApiName: LOAN_OBJECT })
    objectInfo;

    // We keep this wire because picklist definitions rarely change during a session
    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: STATUS_FIELD })
    wiredPicklist({ error, data }) {
        if (data) {
            this.statusOptions = data.values;
        } else if (error) {
            this.showToast('Error', 'Failed to load status options', 'error');
        }
    }

    // Lifecycle hook: Run when the component first inserts into the DOM
    connectedCallback() {
        this.loadApplications();
    }

    // Reusable imperative function that completely bypasses the wire cache
    async loadApplications() {
        this.isLoading = true;
        try {
            const data = await getLoanApplications({ status: this.statusFilter });
            this.applications = data.map(item => ({
                ...item,
                isSelected: false,
                accountName: item.Applicant_Account__r ? item.Applicant_Account__r.Name : '',
                primaryApplicantName: item.Primary_Applicant__r ? item.Primary_Applicant__r.Name : ''
            }));
            this.error = undefined;
        } catch (error) {
            this.error = error.body?.message || 'An error occurred fetching data.';
            this.applications = [];
        } finally {
            this.isLoading = false;
        }
    }

    // Computed Properties
    get totalCount() {
        return this.applications.length;
    }

    get totalAmount() {
        return this.applications.reduce((total, loan) => total + (loan.Loan_Amount__c || 0), 0);
    }

    get hasRecords() {
        return this.applications.length > 0;
    }

    get hasSelectedRecords() {
        return this.selectedCount > 0;
    }

    get selectedCount() {
        return this.applications.filter(loan => loan.isSelected).length;
    }

    get bulkButtonLabel() {
        return `Action Selected (${this.selectedCount})`;
    }

    get isAllSelected() {
        return this.hasRecords && this.applications.every(loan => loan.isSelected);
    }

    get isActionableStatus() {
        return this.statusFilter === 'New' || this.statusFilter === 'Under Review';
    }

    get isReasonRequired() {
        return this.decisionStatus === 'Approved' || this.decisionStatus === 'Rejected';
    }

    get dynamicDecisionOptions() {
        if (this.statusFilter === 'New') {
            return [
                { label: 'Under Review', value: 'Under Review' },
                { label: 'Approve', value: 'Approved' },
                { label: 'Reject', value: 'Rejected' }
            ];
        }
        if (this.statusFilter === 'Under Review') {
            return [
                { label: 'Approve', value: 'Approved' },
                { label: 'Reject', value: 'Rejected' }
            ];
        }
        return [];
    }

    get modalTitle() {
        return this.selectedLoanIds.length > 1
            ? `Bulk State Transition (${this.selectedLoanIds.length} Applications)`
            : 'Transition Application State';
    }

    // Changing filters now explicitly forces a fresh database query instantly
    handleStatusChange(event) {
        this.statusFilter = event.target.value;
        this.loadApplications();
    }

    handleRowSelection(event) {
        const recordId = event.target.value;
        const checked = event.target.checked;

        this.applications = this.applications.map(loan => {
            if (loan.Id === recordId) {
                return { ...loan, isSelected: checked };
            }
            return loan;
        });
    }

    handleSelectAll(event) {
        const checked = event.target.checked;
        this.applications = this.applications.map(loan => ({
            ...loan,
            isSelected: checked
        }));
    }

    openSingleDecisionModal(event) {
        this.selectedLoanIds = [event.target.value];
        this.resetModalForm();
        this.isModalOpen = true;
    }

    openDecisionModal() {
        this.selectedLoanIds = this.applications
            .filter(loan => loan.isSelected)
            .map(loan => loan.Id);
        this.resetModalForm();
        this.isModalOpen = true;
    }

    closeDecisionModal() {
        this.isModalOpen = false;
    }

    resetModalForm() {
        this.decisionStatus = '';
        this.decisionReason = '';
    }

    handleDecisionStatusChange(event) {
        this.decisionStatus = event.target.value;
    }

    handleReasonChange(event) {
        this.decisionReason = event.target.value;
    }

    validateInputs() {
        const fields = [...this.template.querySelectorAll('.validatable-field')];
        return fields.reduce((validSoFar, field) => {
            field.reportValidity();
            return validSoFar && field.checkValidity();
        }, true);
    }

    async handleSubmitDecision() {
        if (!this.validateInputs()) {
            return;
        }

        this.isLoading = true;
        this.isModalOpen = false;

        const decisionPayload = this.selectedLoanIds.map(id => ({
            loanId: id,
            status: this.decisionStatus,
            decisionReason: this.isReasonRequired ? this.decisionReason : ''
        }));

        try {
            await processDecision({ decisions: decisionPayload });

            this.showToast(
                'Success',
                `${decisionPayload.length} application(s) updated successfully.`,
                'success'
            );

            // Re-fetch the current view data natively from the server
            await this.loadApplications();
        } catch (error) {
            this.showToast('Error', error.body.message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}