// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'JB Wholesale · Procurement';

  @override
  String get language => 'Language';

  @override
  String get signOut => 'Sign out';

  @override
  String get retry => 'Try again';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get saved => 'Saved';

  @override
  String get confirm => 'OK';

  @override
  String get edit => 'Edit';

  @override
  String get back => 'Back';

  @override
  String copied(String text) {
    return 'Copied: $text';
  }

  @override
  String get demoBanner => 'Demo mode: sample data, nothing is saved to the server';

  @override
  String get errNetwork => 'Cannot reach the server, please check your connection';

  @override
  String get errAuth => 'Wrong code, or your login has expired';

  @override
  String get errNotAllowed => 'Not allowed (your role cannot do this)';

  @override
  String get errRoleMismatch => 'A wholesaler account cannot be a company member';

  @override
  String get errCompanyNotFound => 'Company not found';

  @override
  String get errCompanySuspended => 'The company is suspended, please contact our support';

  @override
  String get errPlanInactive => 'The company plan is inactive, please pay first';

  @override
  String get errPlanFeature => 'Your plan does not include this feature';

  @override
  String errPlanLimitSites(String max) {
    return 'Your plan allows up to $max sites, please upgrade';
  }

  @override
  String errPlanLimitUsers(String max) {
    return 'Your plan allows up to $max users (members + invites), please upgrade';
  }

  @override
  String get errLastAdmin => 'The company needs at least one admin';

  @override
  String get errSiteOpenDocuments => 'This site still has open orders and cannot be archived';

  @override
  String get errNotFound => 'Not found (someone may have changed it)';

  @override
  String get errAlreadyMember => 'This number is already a member';

  @override
  String get errSsmRegistered => 'This SSM number is already registered';

  @override
  String get errInvalidZone => 'Please choose a delivery zone';

  @override
  String get errInvalidValue => 'Something is not valid, please check';

  @override
  String get errNothingDue => 'Nothing to pay';

  @override
  String get errPaymentNotConfigured => 'Online payment is not available yet, please pay by bank transfer';

  @override
  String get errGateway => 'The payment gateway is unavailable, please try again later';

  @override
  String get errTooManyPayments => 'Too many payment pages, please wait';

  @override
  String get errUseRequisition => 'Company sites order through requisitions';

  @override
  String errUnknown(String code) {
    return 'Something went wrong ($code)';
  }

  @override
  String get loginTitle => 'Procurement sign in';

  @override
  String get loginSubtitle =>
      'Sign in with your phone number and a code. Company members and new companies (register after signing in) are welcome.';

  @override
  String get phoneLabel => 'Phone number';

  @override
  String get phoneInvalid => 'Please enter a Malaysian mobile number, e.g. 012-345 6789';

  @override
  String get sendCode => 'Send code';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get otpLogin => 'Sign in';

  @override
  String get otpResend => 'Resend';

  @override
  String otpResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get changePhone => 'Change number';

  @override
  String get loadingContext => 'Loading…';

  @override
  String get deniedTitle => 'This is a wholesaler account';

  @override
  String get deniedBody => 'The procurement web app is for company staff. Wholesalers please use the mobile app.';

  @override
  String get regTitle => 'Register a company';

  @override
  String get regSubtitle =>
      'You are not a member of any company yet. Register one (you become its admin), or ask your company admin to invite your phone number.';

  @override
  String get regAnotherSubtitle => 'Register another company (you become its admin).';

  @override
  String get regName => 'Company name';

  @override
  String get regType => 'Company type';

  @override
  String get regRegion => 'Region';

  @override
  String get regSsm => 'SSM number (optional)';

  @override
  String get regSsmHelp => 'A company can register once and gets one trial';

  @override
  String get regBillingEmail => 'Billing email';

  @override
  String get regFirstSite => 'First site';

  @override
  String get regFirstSiteHelp => 'Where goods are delivered (you can add more later)';

  @override
  String get regNameRequired => 'Please enter the company name';

  @override
  String get regZoneRequired => 'Please choose the site delivery zone';

  @override
  String get regSubmit => 'Register company';

  @override
  String get regTrialNote =>
      'New companies get a 30-day trial with all Pro features. A phone number or SSM that already had a trial pays the first period first.';

  @override
  String get registerAnother => 'Register another company';

  @override
  String get switchCompany => 'Switch company';

  @override
  String get navHome => 'Home';

  @override
  String get navBrowse => 'Compare prices';

  @override
  String get navSites => 'Sites';

  @override
  String get navMembers => 'Members';

  @override
  String get navBilling => 'Plan & billing';

  @override
  String get navInbox => 'Inbox';

  @override
  String get navCompany => 'Company profile';

  @override
  String homeRoles(String roles) {
    return 'My roles: $roles';
  }

  @override
  String get homeSuspended =>
      'The company is suspended: changes are blocked and sites cannot see prices. Please contact support.';

  @override
  String homeTrial(String date) {
    return 'On trial until $date';
  }

  @override
  String homeActive(String plan, String date) {
    return '$plan, active until $date';
  }

  @override
  String homePastDue(String date) {
    return 'Invoice overdue, grace period until $date';
  }

  @override
  String get homeLapsed => 'Plan inactive: sites cannot see prices, please pay';

  @override
  String get homeManagePlan => 'Plan & billing';

  @override
  String get homePlanManaged => 'The plan is managed by your company admin / finance';

  @override
  String get homePendingApprovals => 'Waiting for my approval';

  @override
  String get homeComingSoon => 'Requisitions and approvals coming soon';

  @override
  String homeOpenInvites(int count) {
    return '$count invites pending';
  }

  @override
  String get homeUnread => 'Unread notifications';

  @override
  String get homeQuickActions => 'Shortcuts';

  @override
  String get homeMySites => 'My sites';

  @override
  String get browseHint =>
      'Pick a site: delivery zone and shipping follow that site. The same item from several wholesalers is grouped and sorted by price per piece.';

  @override
  String get browseSite => 'Site';

  @override
  String get browseSearch => 'Search items or wholesalers';

  @override
  String get browseNoSite => 'No sites yet: add a site to compare prices';

  @override
  String get browseEmpty => 'No items deliver to this site';

  @override
  String get browsePricesHidden => 'The company plan is inactive: prices are hidden. Please pay first.';

  @override
  String browseCompareCount(String name, int count) {
    return '$name ($count offers)';
  }

  @override
  String browsePack(String unit, int count) {
    return '$count pcs / $unit';
  }

  @override
  String get browsePriceHidden => 'Price hidden';

  @override
  String browsePerPiece(String sen) {
    return '$sen sen each';
  }

  @override
  String browseMinQty(int qty) {
    return 'Min. $qty';
  }

  @override
  String browseShipping(String fee, int days) {
    return 'Shipping $fee, $days days';
  }

  @override
  String get browseOutOfStock => 'Out of stock';

  @override
  String get browseCheapest => 'Cheapest';

  @override
  String get sitesHint => 'Each site has its own delivery zone, address and shipping fees.';

  @override
  String sitesLimit(int count, int max) {
    return '($count of $max)';
  }

  @override
  String get sitesAdd => 'Add site';

  @override
  String get sitesEdit => 'Edit site';

  @override
  String get sitesAdded => 'Site added';

  @override
  String get sitesArchive => 'Archive';

  @override
  String get sitesArchived => 'Site archived';

  @override
  String get sitesArchivedTag => 'Archived';

  @override
  String sitesArchiveTitle(String name) {
    return 'Archive \"$name\"?';
  }

  @override
  String get sitesArchiveBody => 'The site can no longer order (history is kept) and stops counting towards your plan.';

  @override
  String get sitesEmpty => 'You have no sites yet';

  @override
  String get sitesEmptyAdmin => 'No sites yet, tap \"Add site\"';

  @override
  String get siteName => 'Site name';

  @override
  String get siteZone => 'Delivery zone';

  @override
  String get siteAddress => 'Address';

  @override
  String get siteContact => 'Contact person';

  @override
  String get sitePhone => 'Site phone';

  @override
  String get siteCode => 'Site code (e.g. KL01)';

  @override
  String get siteCostCenter => 'Cost centre';

  @override
  String get siteRequired => 'Please enter a site name and zone';

  @override
  String get membersHint => 'Roles decide what people can do; members without all sites only manage the chosen sites.';

  @override
  String membersLimit(int max) {
    return '(plan allows $max users)';
  }

  @override
  String get membersTitle => 'Members';

  @override
  String get membersInvite => 'Invite member';

  @override
  String membersEdit(String name) {
    return 'Edit $name';
  }

  @override
  String get membersInvited =>
      'Invited: the number joins automatically after signing in (existing accounts are added now)';

  @override
  String get membersRoles => 'Roles (choose one or more)';

  @override
  String get membersAllSites => 'All sites';

  @override
  String get membersAllSitesForced => 'Admin and finance always see all sites';

  @override
  String get membersActive => 'Active';

  @override
  String get membersInactive => 'Inactive';

  @override
  String get membersRemove => 'Remove';

  @override
  String membersRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get membersRemoveBody => 'They will no longer see this company. Their past records are kept.';

  @override
  String get membersRemoved => 'Removed';

  @override
  String get membersInvites => 'Pending invites';

  @override
  String get membersNoInvites => 'None';

  @override
  String get membersInviteExpired => 'Expired';

  @override
  String membersInviteUntil(String time) {
    return 'Valid until $time';
  }

  @override
  String get membersCancelInvite => 'Cancel invite';

  @override
  String get membersInviteCancelled => 'Invite cancelled';

  @override
  String get membersInviteHelp =>
      'Invites last 14 days. The person joins automatically when they sign in with that phone number.';

  @override
  String get membersSendInvite => 'Send invite';

  @override
  String get membersRoleRequired => 'Choose at least one role';

  @override
  String get membersSiteRequired => 'Choose the sites, or turn on \"All sites\"';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get roleApprover => 'Approver';

  @override
  String get roleFinance => 'Finance';

  @override
  String get roleRequester => 'Requester';

  @override
  String get roleAdminHelp => 'Company profile, sites, members, plan; sees everything';

  @override
  String get roleApproverHelp => 'Approves requisitions for their sites';

  @override
  String get roleFinanceHelp => 'Invoices, payments, matching; sees everything';

  @override
  String get roleRequesterHelp => 'Raises requisitions and receives goods (own sites)';

  @override
  String get typeCorporate => 'Corporate';

  @override
  String get typeFactory => 'Factory';

  @override
  String get typeHotel => 'Hotel';

  @override
  String get typeRestaurantChain => 'Restaurant chain';

  @override
  String get typeGlc => 'GLC';

  @override
  String get typeOther => 'Other';

  @override
  String get subTrialing => 'On trial';

  @override
  String get subActive => 'Active';

  @override
  String get subPastDue => 'Overdue';

  @override
  String get subLapsed => 'Inactive';

  @override
  String get subNone => 'No plan';

  @override
  String get cycleMonthly => 'Monthly';

  @override
  String get cycleAnnual => 'Annual';

  @override
  String get perMonth => '/ month';

  @override
  String get perYear => '/ year';

  @override
  String get planTrial => 'Trial';

  @override
  String get planStarter => 'Starter';

  @override
  String get planPro => 'Pro';

  @override
  String get planEnterprise => 'Enterprise';

  @override
  String get featRequisitions => 'Requisitions & approvals';

  @override
  String get featMultiTier => 'Multi-level approvals';

  @override
  String get featBudgets => 'Budgets';

  @override
  String get featRfq => 'Requests for quotation';

  @override
  String get featReverseAuction => 'Reverse auctions';

  @override
  String get featAiInsights => 'AI approval assistant';

  @override
  String get featAiSpend => 'AI spend analysis';

  @override
  String get featStatements => 'Statements & matching';

  @override
  String get billingHint =>
      'Prices are locked to your account: renew on time and the price stays. Plan changes start next period.';

  @override
  String get billingCurrent => 'Current plan';

  @override
  String get billingCustomPrice => 'Custom price';

  @override
  String get billingUntil => 'Until';

  @override
  String get billingLocked => 'Locked price';

  @override
  String get billingLimits => 'Limits';

  @override
  String billingLimitsValue(String sites, String users) {
    return '$sites sites · $users users';
  }

  @override
  String get billingNext => 'Next period';

  @override
  String get billingNoAccess => 'Not active: sites cannot see prices. Pay the invoice to restore.';

  @override
  String get billingPlans => 'Plans';

  @override
  String get billingQuote => 'Quoted (contact us)';

  @override
  String get billingContactUs => 'For Enterprise please contact us; our team sets it up';

  @override
  String get billingChoose => 'Choose';

  @override
  String billingChooseTitle(String plan) {
    return 'Switch to $plan?';
  }

  @override
  String billingChooseBody(String price, String per) {
    return 'From next period, $price $per (price locked today).';
  }

  @override
  String get billingPlanChanged => 'Plan updated';

  @override
  String get billingCurrentTag => 'Current';

  @override
  String get billingNextTag => 'Next period';

  @override
  String get billingInvoices => 'Invoices';

  @override
  String get billingNoInvoices => 'No invoices yet';

  @override
  String billingDue(String date) {
    return 'Due $date';
  }

  @override
  String billingPaidAt(String time) {
    return 'Paid $time';
  }

  @override
  String get billingPay => 'Pay';

  @override
  String billingPayTitle(String no) {
    return 'Pay invoice $no';
  }

  @override
  String billingPayAmount(String amount) {
    return 'Amount $amount (calculated by the server)';
  }

  @override
  String get billingPayOpened => 'The payment page opened in a new tab (FPX, DuitNow, card). Come back here when done.';

  @override
  String get billingPayOpenThis => 'Please open this payment page (FPX, DuitNow, card):';

  @override
  String get billingPaidRefresh => 'I have paid, refresh';

  @override
  String get billingBankNote => 'You can also pay by bank transfer (quote the invoice number); our team marks it paid.';

  @override
  String get billingPayments => 'Payments';

  @override
  String get billingNoPayments => 'No payments yet';

  @override
  String get invIssued => 'Due';

  @override
  String get invOverdue => 'Overdue';

  @override
  String get invPaid => 'Paid';

  @override
  String get invVoid => 'Void';

  @override
  String get payPending => 'Pending';

  @override
  String get payPaid => 'Paid';

  @override
  String get payFailed => 'Failed';

  @override
  String get payRefunded => 'Refunded';

  @override
  String get inboxHint => 'Your notifications (whether or not the push arrived)';

  @override
  String get inboxEmpty => 'No notifications';

  @override
  String get inboxMarkAll => 'Mark all read';

  @override
  String get inboxAllRead => 'All marked read';

  @override
  String get inboxUnread => 'New';

  @override
  String get inboxGeneric => 'Notification';

  @override
  String inboxInvoiceIssued(String no) {
    return 'Plan invoice $no';
  }

  @override
  String inboxInvoiceIssuedBody(String amount, String date) {
    return 'Amount $amount, due $date';
  }

  @override
  String inboxInvoiceOverdue(String no) {
    return 'Plan invoice $no is overdue';
  }

  @override
  String inboxInvoiceOverdueBody(String amount, String date) {
    return 'Amount $amount, grace period until $date';
  }

  @override
  String get inboxTrialEnding => 'Trial ending soon';

  @override
  String inboxTrialEndingBody(String date) {
    return 'Ends $date, please choose a plan';
  }

  @override
  String inboxTrialEndingChosen(String date) {
    return 'Ends $date, your chosen plan continues after';
  }

  @override
  String inboxPaid(String amount) {
    return 'Payment received $amount';
  }

  @override
  String inboxPaidBody(String no) {
    return 'Invoice $no paid, thank you!';
  }

  @override
  String get companyHint => 'Details used for invoices and e-Invoice.';

  @override
  String get companyReadOnly => 'Only admins can change this.';

  @override
  String get companyLegalName => 'Legal name (as in SSM)';

  @override
  String get companyTin => 'Tax ID (TIN)';

  @override
  String get companySst => 'SST number';

  @override
  String get companyBillingContact => 'Billing contact';

  @override
  String get companyBillingAddress => 'Billing address';

  @override
  String get companyPhone => 'Company phone';

  @override
  String get unitCarton => 'carton';

  @override
  String get unitPack => 'pack';

  @override
  String get unitBag => 'bag';

  @override
  String get unitRoll => 'roll';

  @override
  String get unitBundle => 'bundle';

  @override
  String get unitBox => 'box';

  @override
  String get unitPiece => 'piece';

  @override
  String get unitDozen => 'dozen';

  @override
  String get unitKg => 'kg';
}
