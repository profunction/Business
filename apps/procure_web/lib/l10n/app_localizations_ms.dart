// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malay (`ms`).
class L10nMs extends L10n {
  L10nMs([String locale = 'ms']) : super(locale);

  @override
  String get appTitle => 'JB Wholesale · Perolehan';

  @override
  String get language => 'Bahasa';

  @override
  String get signOut => 'Log keluar';

  @override
  String get retry => 'Cuba lagi';

  @override
  String get cancel => 'Batal';

  @override
  String get save => 'Simpan';

  @override
  String get saved => 'Disimpan';

  @override
  String get confirm => 'OK';

  @override
  String get edit => 'Ubah';

  @override
  String get back => 'Kembali';

  @override
  String copied(String text) {
    return 'Disalin: $text';
  }

  @override
  String get demoBanner => 'Mod demo: data contoh, tiada apa disimpan ke pelayan';

  @override
  String get errNetwork => 'Tidak dapat menghubungi pelayan, sila semak sambungan';

  @override
  String get errAuth => 'Kod salah, atau log masuk telah tamat';

  @override
  String get errNotAllowed => 'Tidak dibenarkan (peranan anda tidak boleh)';

  @override
  String get errRoleMismatch => 'Akaun pemborong tidak boleh menjadi ahli syarikat';

  @override
  String get errCompanyNotFound => 'Syarikat tidak dijumpai';

  @override
  String get errCompanySuspended => 'Syarikat digantung, sila hubungi sokongan kami';

  @override
  String get errPlanInactive => 'Pelan syarikat tidak aktif, sila bayar dahulu';

  @override
  String get errPlanFeature => 'Pelan anda tidak termasuk ciri ini';

  @override
  String errPlanLimitSites(String max) {
    return 'Pelan anda membenarkan sehingga $max cawangan, sila naik taraf';
  }

  @override
  String errPlanLimitUsers(String max) {
    return 'Pelan anda membenarkan sehingga $max pengguna (ahli + jemputan), sila naik taraf';
  }

  @override
  String get errLastAdmin => 'Syarikat perlu sekurang-kurangnya seorang pentadbir';

  @override
  String get errSiteOpenDocuments => 'Cawangan ini masih ada pesanan terbuka dan tidak boleh diarkibkan';

  @override
  String get errNotFound => 'Tidak dijumpai (mungkin telah diubah)';

  @override
  String get errAlreadyMember => 'Nombor ini sudah menjadi ahli';

  @override
  String get errSsmRegistered => 'Nombor SSM ini sudah didaftarkan';

  @override
  String get errInvalidZone => 'Sila pilih zon penghantaran';

  @override
  String get errInvalidValue => 'Ada maklumat tidak sah, sila semak';

  @override
  String get errNothingDue => 'Tiada apa untuk dibayar';

  @override
  String get errPaymentNotConfigured => 'Bayaran dalam talian belum tersedia, sila bayar melalui pindahan bank';

  @override
  String get errGateway => 'Gerbang pembayaran tidak tersedia, sila cuba lagi nanti';

  @override
  String get errTooManyPayments => 'Terlalu banyak halaman bayaran, sila tunggu';

  @override
  String get errUseRequisition => 'Cawangan syarikat memesan melalui permohonan';

  @override
  String errUnknown(String code) {
    return 'Ralat ($code)';
  }

  @override
  String get loginTitle => 'Log masuk perolehan';

  @override
  String get loginSubtitle =>
      'Log masuk dengan nombor telefon dan kod. Ahli syarikat dan syarikat baharu (daftar selepas log masuk) dialu-alukan.';

  @override
  String get phoneLabel => 'Nombor telefon';

  @override
  String get phoneInvalid => 'Sila masukkan nombor telefon bimbit Malaysia, cth. 012-345 6789';

  @override
  String get sendCode => 'Hantar kod';

  @override
  String get otpTitle => 'Masukkan kod';

  @override
  String otpSentTo(String phone) {
    return 'Kod dihantar ke $phone';
  }

  @override
  String get otpLogin => 'Log masuk';

  @override
  String get otpResend => 'Hantar semula';

  @override
  String otpResendIn(int seconds) {
    return 'Hantar semula dalam ${seconds}s';
  }

  @override
  String get changePhone => 'Tukar nombor';

  @override
  String get loadingContext => 'Memuatkan…';

  @override
  String get deniedTitle => 'Ini akaun pemborong';

  @override
  String get deniedBody => 'Web perolehan untuk kakitangan syarikat. Pemborong sila guna aplikasi mudah alih.';

  @override
  String get regTitle => 'Daftar syarikat';

  @override
  String get regSubtitle =>
      'Anda belum menjadi ahli mana-mana syarikat. Daftar satu (anda menjadi pentadbir), atau minta pentadbir syarikat menjemput nombor anda.';

  @override
  String get regAnotherSubtitle => 'Daftar syarikat lain (anda menjadi pentadbir).';

  @override
  String get regName => 'Nama syarikat';

  @override
  String get regType => 'Jenis syarikat';

  @override
  String get regRegion => 'Wilayah';

  @override
  String get regSsm => 'Nombor SSM (pilihan)';

  @override
  String get regSsmHelp => 'Syarikat boleh mendaftar sekali dan mendapat satu percubaan';

  @override
  String get regBillingEmail => 'E-mel bil';

  @override
  String get regFirstSite => 'Cawangan pertama';

  @override
  String get regFirstSiteHelp => 'Tempat barang dihantar (boleh tambah kemudian)';

  @override
  String get regNameRequired => 'Sila masukkan nama syarikat';

  @override
  String get regZoneRequired => 'Sila pilih zon penghantaran cawangan';

  @override
  String get regSubmit => 'Daftar syarikat';

  @override
  String get regTrialNote =>
      'Syarikat baharu mendapat percubaan 30 hari dengan semua ciri Pro. Nombor telefon atau SSM yang pernah mencuba perlu bayar tempoh pertama dahulu.';

  @override
  String get registerAnother => 'Daftar syarikat lain';

  @override
  String get switchCompany => 'Tukar syarikat';

  @override
  String get navHome => 'Utama';

  @override
  String get navBrowse => 'Banding harga';

  @override
  String get navSites => 'Cawangan';

  @override
  String get navMembers => 'Ahli';

  @override
  String get navBilling => 'Pelan & bil';

  @override
  String get navInbox => 'Peti masuk';

  @override
  String get navCompany => 'Profil syarikat';

  @override
  String homeRoles(String roles) {
    return 'Peranan saya: $roles';
  }

  @override
  String get homeSuspended =>
      'Syarikat digantung: perubahan disekat dan cawangan tidak nampak harga. Sila hubungi sokongan.';

  @override
  String homeTrial(String date) {
    return 'Dalam percubaan hingga $date';
  }

  @override
  String homeActive(String plan, String date) {
    return '$plan, aktif hingga $date';
  }

  @override
  String homePastDue(String date) {
    return 'Invois lewat, tempoh tangguh hingga $date';
  }

  @override
  String get homeLapsed => 'Pelan tidak aktif: cawangan tidak nampak harga, sila bayar';

  @override
  String get homeManagePlan => 'Pelan & bil';

  @override
  String get homePlanManaged => 'Pelan diurus oleh pentadbir / kewangan syarikat anda';

  @override
  String get homePendingApprovals => 'Menunggu kelulusan saya';

  @override
  String get homeComingSoon => 'Permohonan dan kelulusan akan datang';

  @override
  String homeOpenInvites(int count) {
    return '$count jemputan belum diterima';
  }

  @override
  String get homeUnread => 'Pemberitahuan belum dibaca';

  @override
  String get homeQuickActions => 'Pintasan';

  @override
  String get homeMySites => 'Cawangan saya';

  @override
  String get browseHint =>
      'Pilih cawangan: zon penghantaran dan caj ikut cawangan itu. Barang yang sama dari beberapa pemborong dikumpul dan disusun ikut harga seunit.';

  @override
  String get browseSite => 'Cawangan';

  @override
  String get browseSearch => 'Cari barang atau pemborong';

  @override
  String get browseNoSite => 'Belum ada cawangan: tambah cawangan untuk banding harga';

  @override
  String get browseEmpty => 'Tiada barang dihantar ke cawangan ini';

  @override
  String get browsePricesHidden => 'Pelan syarikat tidak aktif: harga disembunyikan. Sila bayar dahulu.';

  @override
  String browseCompareCount(String name, int count) {
    return '$name ($count tawaran)';
  }

  @override
  String browsePack(String unit, int count) {
    return '$count unit / $unit';
  }

  @override
  String get browsePriceHidden => 'Harga tersembunyi';

  @override
  String browsePerPiece(String sen) {
    return '$sen sen seunit';
  }

  @override
  String browseMinQty(int qty) {
    return 'Min. $qty';
  }

  @override
  String browseShipping(String fee, int days) {
    return 'Penghantaran $fee, $days hari';
  }

  @override
  String get browseOutOfStock => 'Kehabisan stok';

  @override
  String get browseCheapest => 'Paling murah';

  @override
  String get sitesHint => 'Setiap cawangan ada zon penghantaran, alamat dan caj sendiri.';

  @override
  String sitesLimit(int count, int max) {
    return '($count daripada $max)';
  }

  @override
  String get sitesAdd => 'Tambah cawangan';

  @override
  String get sitesEdit => 'Ubah cawangan';

  @override
  String get sitesAdded => 'Cawangan ditambah';

  @override
  String get sitesArchive => 'Arkibkan';

  @override
  String get sitesArchived => 'Cawangan diarkibkan';

  @override
  String get sitesArchivedTag => 'Diarkibkan';

  @override
  String sitesArchiveTitle(String name) {
    return 'Arkibkan \"$name\"?';
  }

  @override
  String get sitesArchiveBody => 'Cawangan tidak boleh memesan lagi (rekod disimpan) dan tidak dikira dalam pelan.';

  @override
  String get sitesEmpty => 'Anda belum ada cawangan';

  @override
  String get sitesEmptyAdmin => 'Belum ada cawangan, tekan \"Tambah cawangan\"';

  @override
  String get siteName => 'Nama cawangan';

  @override
  String get siteZone => 'Zon penghantaran';

  @override
  String get siteAddress => 'Alamat';

  @override
  String get siteContact => 'Orang dihubungi';

  @override
  String get sitePhone => 'Telefon cawangan';

  @override
  String get siteCode => 'Kod cawangan (cth. KL01)';

  @override
  String get siteCostCenter => 'Pusat kos';

  @override
  String get siteRequired => 'Sila masukkan nama cawangan dan zon';

  @override
  String get membersHint =>
      'Peranan menentukan apa yang boleh dibuat; ahli tanpa semua cawangan hanya urus cawangan dipilih.';

  @override
  String membersLimit(int max) {
    return '(pelan membenarkan $max pengguna)';
  }

  @override
  String get membersTitle => 'Ahli';

  @override
  String get membersInvite => 'Jemput ahli';

  @override
  String membersEdit(String name) {
    return 'Ubah $name';
  }

  @override
  String get membersInvited => 'Dijemput: nombor ini menyertai selepas log masuk (akaun sedia ada ditambah sekarang)';

  @override
  String get membersRoles => 'Peranan (pilih satu atau lebih)';

  @override
  String get membersAllSites => 'Semua cawangan';

  @override
  String get membersAllSitesForced => 'Pentadbir dan kewangan sentiasa nampak semua cawangan';

  @override
  String get membersActive => 'Aktif';

  @override
  String get membersInactive => 'Tidak aktif';

  @override
  String get membersRemove => 'Buang';

  @override
  String membersRemoveTitle(String name) {
    return 'Buang $name?';
  }

  @override
  String get membersRemoveBody => 'Mereka tidak lagi nampak syarikat ini. Rekod lama disimpan.';

  @override
  String get membersRemoved => 'Dibuang';

  @override
  String get membersInvites => 'Jemputan belum diterima';

  @override
  String get membersNoInvites => 'Tiada';

  @override
  String get membersInviteExpired => 'Tamat tempoh';

  @override
  String membersInviteUntil(String time) {
    return 'Sah hingga $time';
  }

  @override
  String get membersCancelInvite => 'Batal jemputan';

  @override
  String get membersInviteCancelled => 'Jemputan dibatalkan';

  @override
  String get membersInviteHelp =>
      'Jemputan sah 14 hari. Orang itu menyertai secara automatik apabila log masuk dengan nombor itu.';

  @override
  String get membersSendInvite => 'Hantar jemputan';

  @override
  String get membersRoleRequired => 'Pilih sekurang-kurangnya satu peranan';

  @override
  String get membersSiteRequired => 'Pilih cawangan, atau hidupkan \"Semua cawangan\"';

  @override
  String get roleAdmin => 'Pentadbir';

  @override
  String get roleApprover => 'Pelulus';

  @override
  String get roleFinance => 'Kewangan';

  @override
  String get roleRequester => 'Pemohon';

  @override
  String get roleAdminHelp => 'Profil, cawangan, ahli, pelan; nampak semua';

  @override
  String get roleApproverHelp => 'Meluluskan permohonan cawangan sendiri';

  @override
  String get roleFinanceHelp => 'Invois, bayaran, padanan; nampak semua';

  @override
  String get roleRequesterHelp => 'Buat permohonan dan terima barang (cawangan sendiri)';

  @override
  String get typeCorporate => 'Korporat';

  @override
  String get typeFactory => 'Kilang';

  @override
  String get typeHotel => 'Hotel';

  @override
  String get typeRestaurantChain => 'Rangkaian restoran';

  @override
  String get typeGlc => 'GLC';

  @override
  String get typeOther => 'Lain-lain';

  @override
  String get subTrialing => 'Dalam percubaan';

  @override
  String get subActive => 'Aktif';

  @override
  String get subPastDue => 'Lewat';

  @override
  String get subLapsed => 'Tidak aktif';

  @override
  String get subNone => 'Tiada pelan';

  @override
  String get cycleMonthly => 'Bulanan';

  @override
  String get cycleAnnual => 'Tahunan';

  @override
  String get perMonth => '/ bulan';

  @override
  String get perYear => '/ tahun';

  @override
  String get planTrial => 'Percubaan';

  @override
  String get planStarter => 'Permulaan';

  @override
  String get planPro => 'Pro';

  @override
  String get planEnterprise => 'Perusahaan';

  @override
  String get featRequisitions => 'Permohonan & kelulusan';

  @override
  String get featMultiTier => 'Kelulusan berbilang peringkat';

  @override
  String get featBudgets => 'Bajet';

  @override
  String get featRfq => 'Permintaan sebut harga';

  @override
  String get featReverseAuction => 'Lelongan terbalik';

  @override
  String get featAiInsights => 'Pembantu kelulusan AI';

  @override
  String get featAiSpend => 'Analisis perbelanjaan AI';

  @override
  String get featStatements => 'Penyata & padanan';

  @override
  String get billingHint =>
      'Harga dikunci pada akaun anda: perbaharui tepat masa dan harga kekal. Tukar pelan bermula tempoh seterusnya.';

  @override
  String get billingCurrent => 'Pelan semasa';

  @override
  String get billingCustomPrice => 'Harga khas';

  @override
  String get billingUntil => 'Hingga';

  @override
  String get billingLocked => 'Harga terkunci';

  @override
  String get billingLimits => 'Had';

  @override
  String billingLimitsValue(String sites, String users) {
    return '$sites cawangan · $users pengguna';
  }

  @override
  String get billingNext => 'Tempoh seterusnya';

  @override
  String get billingNoAccess => 'Tidak aktif: cawangan tidak nampak harga. Bayar invois untuk pulihkan.';

  @override
  String get billingPlans => 'Pelan';

  @override
  String get billingQuote => 'Sebut harga (hubungi kami)';

  @override
  String get billingContactUs => 'Untuk Perusahaan sila hubungi kami; pasukan kami akan menetapkannya';

  @override
  String get billingChoose => 'Pilih';

  @override
  String billingChooseTitle(String plan) {
    return 'Tukar ke $plan?';
  }

  @override
  String billingChooseBody(String price, String per) {
    return 'Mulai tempoh seterusnya, $price $per (harga dikunci hari ini).';
  }

  @override
  String get billingPlanChanged => 'Pelan dikemas kini';

  @override
  String get billingCurrentTag => 'Semasa';

  @override
  String get billingNextTag => 'Tempoh seterusnya';

  @override
  String get billingInvoices => 'Invois';

  @override
  String get billingNoInvoices => 'Belum ada invois';

  @override
  String billingDue(String date) {
    return 'Tarikh akhir $date';
  }

  @override
  String billingPaidAt(String time) {
    return 'Dibayar $time';
  }

  @override
  String get billingPay => 'Bayar';

  @override
  String billingPayTitle(String no) {
    return 'Bayar invois $no';
  }

  @override
  String billingPayAmount(String amount) {
    return 'Jumlah $amount (dikira oleh pelayan)';
  }

  @override
  String get billingPayOpened =>
      'Halaman bayaran dibuka dalam tab baharu (FPX, DuitNow, kad). Kembali ke sini selepas selesai.';

  @override
  String get billingPayOpenThis => 'Sila buka halaman bayaran ini (FPX, DuitNow, kad):';

  @override
  String get billingPaidRefresh => 'Saya sudah bayar, muat semula';

  @override
  String get billingBankNote =>
      'Anda juga boleh bayar melalui pindahan bank (nyatakan nombor invois); pasukan kami akan tandakan dibayar.';

  @override
  String get billingPayments => 'Bayaran';

  @override
  String get billingNoPayments => 'Belum ada bayaran';

  @override
  String get invIssued => 'Belum bayar';

  @override
  String get invOverdue => 'Lewat';

  @override
  String get invPaid => 'Dibayar';

  @override
  String get invVoid => 'Batal';

  @override
  String get payPending => 'Menunggu';

  @override
  String get payPaid => 'Dibayar';

  @override
  String get payFailed => 'Gagal';

  @override
  String get payRefunded => 'Dipulangkan';

  @override
  String get inboxHint => 'Pemberitahuan anda (sama ada push diterima atau tidak)';

  @override
  String get inboxEmpty => 'Tiada pemberitahuan';

  @override
  String get inboxMarkAll => 'Tanda semua dibaca';

  @override
  String get inboxAllRead => 'Semua ditanda dibaca';

  @override
  String get inboxUnread => 'Baharu';

  @override
  String get inboxGeneric => 'Pemberitahuan';

  @override
  String inboxInvoiceIssued(String no) {
    return 'Invois pelan $no';
  }

  @override
  String inboxInvoiceIssuedBody(String amount, String date) {
    return 'Jumlah $amount, tarikh akhir $date';
  }

  @override
  String inboxInvoiceOverdue(String no) {
    return 'Invois pelan $no lewat';
  }

  @override
  String inboxInvoiceOverdueBody(String amount, String date) {
    return 'Jumlah $amount, tangguh hingga $date';
  }

  @override
  String get inboxTrialEnding => 'Percubaan hampir tamat';

  @override
  String inboxTrialEndingBody(String date) {
    return 'Tamat $date, sila pilih pelan';
  }

  @override
  String inboxTrialEndingChosen(String date) {
    return 'Tamat $date, pelan pilihan diteruskan selepas itu';
  }

  @override
  String inboxPaid(String amount) {
    return 'Bayaran diterima $amount';
  }

  @override
  String inboxPaidBody(String no) {
    return 'Invois $no dibayar, terima kasih!';
  }

  @override
  String get companyHint => 'Butiran untuk invois dan e-Invois.';

  @override
  String get companyReadOnly => 'Hanya pentadbir boleh mengubah.';

  @override
  String get companyLegalName => 'Nama berdaftar (seperti SSM)';

  @override
  String get companyTin => 'No. cukai (TIN)';

  @override
  String get companySst => 'Nombor SST';

  @override
  String get companyBillingContact => 'Orang hubungan bil';

  @override
  String get companyBillingAddress => 'Alamat bil';

  @override
  String get companyPhone => 'Telefon syarikat';

  @override
  String get unitCarton => 'karton';

  @override
  String get unitPack => 'pek';

  @override
  String get unitBag => 'beg';

  @override
  String get unitRoll => 'gulung';

  @override
  String get unitBundle => 'ikat';

  @override
  String get unitBox => 'kotak';

  @override
  String get unitPiece => 'biji';

  @override
  String get unitDozen => 'dozen';

  @override
  String get unitKg => 'kg';
}
