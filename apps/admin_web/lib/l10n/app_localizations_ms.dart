// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malay (`ms`).
class L10nMs extends L10n {
  L10nMs([String locale = 'ms']) : super(locale);

  @override
  String get appTitle => 'JB Wholesale · Admin';

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
  String get close => 'Tutup';

  @override
  String get confirm => 'Sahkan';

  @override
  String get all => 'Semua';

  @override
  String get searchHint => 'Cari';

  @override
  String get saved => 'Disimpan';

  @override
  String copied(String text) {
    return 'Disalin: $text';
  }

  @override
  String get demoBanner => 'Mod demo: data contoh, tiada apa dihantar ke pelayan';

  @override
  String get errNetwork => 'Tidak dapat capai pelayan. Semak sambungan.';

  @override
  String get errAuth => 'Kod salah, atau log masuk telah tamat';

  @override
  String get errNotAllowed => 'Tidak dibenarkan (admin sahaja)';

  @override
  String get errPriceChanged => 'Harga baru berubah. Semak jumlah baharu dan cuba lagi.';

  @override
  String get errCartHasProblems => 'Troli ada masalah. Lihat setiap baris.';

  @override
  String get errCartEmpty => 'Troli kosong';

  @override
  String get errInvalidTransition => 'Pesanan tidak boleh ditukar ke status itu sekarang';

  @override
  String get errInvalidRate => 'Kadar mesti 0%–20%, hingga 2 perpuluhan';

  @override
  String get errInvalidDays => 'Hari mesti 1–90';

  @override
  String get errInvalidMonths => 'Bulan mesti 1–24';

  @override
  String get errInvalidAmount => 'Jumlah tidak sah';

  @override
  String get errDuplicateReference => 'Nombor rujukan ini sudah direkodkan';

  @override
  String get errSubscriptionState => 'Langganan ini tidak boleh diubah begitu sekarang';

  @override
  String get errSubscriptionOpen => 'Kedai ini sudah ada langganan baharu';

  @override
  String get errInvoiceState => 'Invois tidak boleh diubah begitu sekarang';

  @override
  String get errFoundingFull => 'Kuota ahli pengasas penuh';

  @override
  String get errInvalidProduct => 'Produk tidak sah: semak nama, unit, harga dan kuantiti';

  @override
  String get errInvalidNote => 'Sila tulis catatan';

  @override
  String get errNoPricingPlan => 'Pelan harga belum ditetapkan (hubungi teknikal)';

  @override
  String errUnknown(String code) {
    return 'Ada masalah ($code)';
  }

  @override
  String get loginTitle => 'Log masuk admin';

  @override
  String get loginSubtitle => 'Log masuk dengan nombor telefon dan kod. Akaun admin sahaja.';

  @override
  String get phoneLabel => 'Nombor telefon';

  @override
  String get phoneInvalid => 'Masukkan nombor telefon Malaysia, cth. 012-345 6789';

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
  String get deniedTitle => 'Akaun ini bukan admin';

  @override
  String get deniedBody =>
      'Laman admin untuk kakitangan admin sahaja. Pemilik kedai dan pemborong sila guna aplikasi telefon.';

  @override
  String get loadingContext => 'Memuatkan…';

  @override
  String get navDashboard => 'Papan pemuka';

  @override
  String get navOrders => 'Semua pesanan';

  @override
  String get navFollowup => 'Susulan';

  @override
  String get navPlaceOrder => 'Pesan bagi kedai';

  @override
  String get navWholesalers => 'Pemborong';

  @override
  String get navSubscriptions => 'Langganan';

  @override
  String get navCommission => 'Komisen';

  @override
  String get navAudit => 'Log audit';

  @override
  String dashUnconfirmed(int minutes) {
    return 'Belum disahkan > $minutes min';
  }

  @override
  String get dashPendingOrders => 'Pesanan menunggu';

  @override
  String get dashPendingWholesalers => 'Pemborong untuk diluluskan';

  @override
  String get dashTodayOrders => 'Pesanan hari ini';

  @override
  String get dashTodayTotal => 'Jumlah hari ini';

  @override
  String get dashMonthGmv => 'Barang dihantar bulan ini';

  @override
  String get dashMonthCommission => 'Komisen bulan ini';

  @override
  String get dashSubscriptions => 'Langganan';

  @override
  String get subTrialing => 'Percubaan';

  @override
  String get subActive => 'Aktif';

  @override
  String get subPastDue => 'Tertunggak';

  @override
  String get subLapsed => 'Tamat';

  @override
  String get subNone => 'Tiada langganan';

  @override
  String get subFounding => 'Harga pengasas';

  @override
  String get statusPending => 'Menunggu';

  @override
  String get statusConfirmed => 'Disahkan';

  @override
  String get statusOutOfStock => 'Habis stok';

  @override
  String get statusDelivering => 'Dalam penghantaran';

  @override
  String get statusDelivered => 'Dihantar';

  @override
  String get statusCancelled => 'Dibatalkan';

  @override
  String get sourceApp => 'Aplikasi';

  @override
  String get sourceVoice => 'Suara';

  @override
  String get sourceWhatsapp => 'WhatsApp';

  @override
  String get sourceAdmin => 'Admin';

  @override
  String get sourceReorder => 'Pesan semula';

  @override
  String get channelApp => 'Aplikasi';

  @override
  String get channelWhatsapp => 'WhatsApp';

  @override
  String get channelAdmin => 'Admin';

  @override
  String get channelSystem => 'Sistem';

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

  @override
  String get stockIn => 'Ada stok';

  @override
  String get stockLow => 'Stok rendah';

  @override
  String get stockOut => 'Habis stok';

  @override
  String get productActive => 'Dijual';

  @override
  String get productDraft => 'Draf';

  @override
  String get productArchived => 'Tidak dijual';

  @override
  String get filterFrom => 'Dari';

  @override
  String get filterTo => 'Hingga';

  @override
  String get filterWholesaler => 'Pemborong';

  @override
  String get filterShop => 'Kedai';

  @override
  String get filterStatus => 'Status';

  @override
  String get filterSource => 'Sumber';

  @override
  String filterUnconfirmed(int minutes) {
    return 'Hanya belum disahkan > $minutes min';
  }

  @override
  String get filterClear => 'Kosongkan penapis';

  @override
  String ordersTotal(int count) {
    return '$count pesanan';
  }

  @override
  String get ordersEmpty => 'Tiada pesanan sepadan';

  @override
  String get colOrderNo => 'No. pesanan';

  @override
  String get colCreated => 'Dibuat';

  @override
  String get colShop => 'Kedai';

  @override
  String get colWholesaler => 'Pemborong';

  @override
  String get colStatus => 'Status';

  @override
  String get colSource => 'Sumber';

  @override
  String get colTotal => 'Jumlah';

  @override
  String get pagePrev => 'Sebelum';

  @override
  String get pageNext => 'Seterusnya';

  @override
  String pageRange(int from, int to, int total) {
    return '$from–$to daripada $total';
  }

  @override
  String followupHint(int minutes) {
    return 'Pesanan menunggu lebih $minutes minit. Telefon pemborong, kemudian tulis catatan.';
  }

  @override
  String get followupEmpty => 'Tiada susulan';

  @override
  String pendingFor(int minutes) {
    return 'Menunggu $minutes min';
  }

  @override
  String get logFollowup => 'Rekod susulan';

  @override
  String get followupNoteLabel => 'Catatan (cth. pemborong akan sahkan sebelum 3 petang)';

  @override
  String lastFollowup(String time, String note) {
    return 'Susulan terakhir $time: $note';
  }

  @override
  String get openOrder => 'Buka pesanan';

  @override
  String phoneOf(String name) {
    return 'Telefon $name';
  }

  @override
  String orderTitle(String orderNo) {
    return 'Pesanan $orderNo';
  }

  @override
  String get itemsTitle => 'Barang';

  @override
  String get eventsTitle => 'Sejarah';

  @override
  String get goodsSubtotal => 'Barang';

  @override
  String get shippingFee => 'Penghantaran';

  @override
  String get totalLabel => 'Jumlah';

  @override
  String get expectedDelivery => 'Jangkaan penghantaran';

  @override
  String get noteLabel => 'Catatan';

  @override
  String get outOfStockTag => 'Habis stok';

  @override
  String get actConfirm => 'Sahkan bagi pemborong';

  @override
  String get actConfirmHint => 'Tandakan barang yang habis stok (tidak dikenakan). Semua ditanda = habis stok.';

  @override
  String get actOutOfStock => 'Seluruh pesanan habis stok';

  @override
  String get actDelivering => 'Dalam penghantaran';

  @override
  String get actDelivered => 'Tandakan dihantar';

  @override
  String get actCancel => 'Batalkan pesanan';

  @override
  String get cancelReasonLabel => 'Sebab (ditunjukkan kepada pemborong)';

  @override
  String statusUpdated(String status) {
    return 'Status dikemas kini: $status';
  }

  @override
  String get chooseShop => 'Pilih kedai';

  @override
  String get shopSearchHint => 'Nama kedai atau telefon';

  @override
  String get changeShop => 'Tukar kedai';

  @override
  String get shopNoApp => 'Tiada aplikasi';

  @override
  String get shopLocked => 'Belum bayar: hanya boleh pesan dari pemborong percuma';

  @override
  String get offersSearchHint => 'Cari produk';

  @override
  String get offersEmpty => 'Tiada produk dihantar ke kedai ini';

  @override
  String get priceHidden => 'Harga tersembunyi';

  @override
  String perPiece(String sen) {
    return '$sen sen sebiji';
  }

  @override
  String minOrderQty(int qty) {
    return 'Min $qty';
  }

  @override
  String get add => 'Tambah';

  @override
  String get cartTitle => 'Troli';

  @override
  String get cartEmpty => 'Troli kosong';

  @override
  String get clearCart => 'Kosongkan';

  @override
  String get orderNoteLabel => 'Catatan (ditunjukkan kepada pemborong)';

  @override
  String placeOrderButton(String amount) {
    return 'Buat pesanan $amount';
  }

  @override
  String get placedTitle => 'Pesanan dibuat';

  @override
  String placedBody(int count) {
    return 'Dibahagi kepada $count pesanan; pemborong dimaklumkan:';
  }

  @override
  String get problemProductUnavailable => 'Produk tiada';

  @override
  String get problemNotDelivering => 'Tidak menghantar ke zon kedai ini';

  @override
  String get problemWholesalerLocked => 'Belum bayar: bukan pemborong percuma';

  @override
  String get problemOutOfStock => 'Habis stok';

  @override
  String problemBelowMinQty(int qty) {
    return 'Bawah minimum $qty';
  }

  @override
  String problemBelowMinOrder(String amount) {
    return '$amount lagi untuk capai pesanan minimum';
  }

  @override
  String get wsStatusPending => 'Menunggu';

  @override
  String get wsStatusActive => 'Aktif';

  @override
  String get wsStatusSuspended => 'Digantung';

  @override
  String get wsApprove => 'Luluskan';

  @override
  String get wsReject => 'Tolak';

  @override
  String get wsSuspend => 'Gantung';

  @override
  String get wsReactivate => 'Aktifkan semula';

  @override
  String get wsNoteLabel => 'Sebab (disimpan dalam log audit)';

  @override
  String wsCommission(String rate) {
    return 'Komisen $rate';
  }

  @override
  String get wsRateOverride => 'Khas';

  @override
  String get wsRateFounding => 'Pengasas';

  @override
  String get wsRateIndustry => 'Lalai industri';

  @override
  String get wsSetRate => 'Tetapkan kadar komisen';

  @override
  String get wsRateLabel => 'Kadar % (kosong = lalai)';

  @override
  String wsRateDefaults(String industry, String founding) {
    return 'Industri $industry, pengasas $founding';
  }

  @override
  String get wsFounding => 'Ahli pengasas';

  @override
  String wsFoundingNo(int no) {
    return 'Pengasas #$no';
  }

  @override
  String get wsWhatsappOptIn => 'Setuju WhatsApp';

  @override
  String wsProducts(int count) {
    return 'Produk ($count)';
  }

  @override
  String wsPendingOrders(int count) {
    return '$count menunggu';
  }

  @override
  String get wsEmpty => 'Tiada pemborong';

  @override
  String productsTitle(String name) {
    return 'Produk $name';
  }

  @override
  String get productsHint => 'Perubahan dibuat bagi pihak pemborong dan disimpan dalam log audit.';

  @override
  String get productNew => 'Produk baharu';

  @override
  String get productEdit => 'Ubah produk';

  @override
  String get productName => 'Nama';

  @override
  String get productUnit => 'Unit';

  @override
  String get productPackQty => 'Biji seunit';

  @override
  String get productPrice => 'Harga (RM)';

  @override
  String get productMinQty => 'Kuantiti minimum';

  @override
  String get productStock => 'Stok';

  @override
  String get productStatus => 'Penyenaraian';

  @override
  String get productsEmpty => 'Belum ada produk';

  @override
  String productPerUnit(String price, String unit, int qty) {
    return '$price / $unit ($qty biji)';
  }

  @override
  String get subsFoundingOnly => 'Harga pengasas sahaja';

  @override
  String get colPlan => 'Harga terkunci';

  @override
  String get colTrialEnds => 'Percubaan tamat';

  @override
  String get colPeriodEnd => 'Dibayar hingga';

  @override
  String get colLastPayment => 'Bayaran terakhir';

  @override
  String get subExtendTrial => 'Lanjutkan percubaan';

  @override
  String get subDaysLabel => 'Hari ditambah (1–90)';

  @override
  String get subMarkPaid => 'Tandakan dibayar';

  @override
  String get subMonthsLabel => 'Bulan';

  @override
  String get subAmountLabel => 'Jumlah RM (kosong = harga terkunci x bulan)';

  @override
  String get subMethodLabel => 'Kaedah bayaran';

  @override
  String get subReferenceLabel => 'Rujukan (no. pindahan bank)';

  @override
  String get subLapsedNewPrice => 'Tamat: bayaran memulakan langganan baharu pada harga hari ini.';

  @override
  String get subCancel => 'Batalkan langganan';

  @override
  String get subCancelConfirm => 'Ia berhenti sekarang. Kembali nanti bermakna langganan baharu pada harga hari itu.';

  @override
  String get subReasonLabel => 'Sebab';

  @override
  String get subSetFounding => 'Harga pengasas';

  @override
  String get subLockedPriceLabel => 'Harga terkunci RM (kosong = tidak berubah)';

  @override
  String get subsEmpty => 'Tiada langganan';

  @override
  String get methodFpx => 'FPX';

  @override
  String get methodDuitnow => 'DuitNow';

  @override
  String get methodEwallet => 'E-dompet';

  @override
  String get methodCard => 'Kad';

  @override
  String get methodOther => 'Tunai / lain-lain';

  @override
  String get commissionHint =>
      'Barang dihantar (tanpa penghantaran) dan komisen setiap pemborong bulan ini. Kadar disimpan semasa penghantaran.';

  @override
  String get prevMonth => 'Bulan sebelum';

  @override
  String get nextMonth => 'Bulan seterusnya';

  @override
  String get colOrders => 'Pesanan dihantar';

  @override
  String get colGmv => 'Barang (tanpa penghantaran)';

  @override
  String get colRate => 'Kadar';

  @override
  String get colCommission => 'Komisen';

  @override
  String get colInvoice => 'Invois';

  @override
  String get colBillingName => 'Nama bil';

  @override
  String get colSsm => 'No. SSM';

  @override
  String get colEmail => 'E-mel';

  @override
  String get colPeriod => 'Tempoh';

  @override
  String get colInvoiceStatus => 'Status invois';

  @override
  String get commissionTotal => 'Jumlah';

  @override
  String get exportCsv => 'Eksport CSV (semua)';

  @override
  String get exportPdf => 'PDF invois';

  @override
  String exported(String name) {
    return 'Dimuat turun $name';
  }

  @override
  String get exportUnsupported => 'Muat turun hanya dalam versi web';

  @override
  String get generateInvoices => 'Jana invois draf';

  @override
  String invoicesGenerated(int count) {
    return '$count invois draf dijana / dikemas kini';
  }

  @override
  String get issueInvoice => 'Keluarkan invois';

  @override
  String get markInvoicePaid => 'Tandakan dibayar';

  @override
  String get invoiceDraft => 'Draf';

  @override
  String get invoiceIssued => 'Dikeluarkan';

  @override
  String get invoicePaid => 'Dibayar';

  @override
  String get invoiceOverdue => 'Tertunggak';

  @override
  String get invoiceVoid => 'Batal';

  @override
  String get invoiceNone => 'Belum ada invois';

  @override
  String get commissionEmpty => 'Tiada pesanan dihantar bulan ini';

  @override
  String get pdfInvoiceTitle => 'Invois komisen';

  @override
  String get pdfBillTo => 'Bil kepada';

  @override
  String get pdfInvoiceNo => 'No. invois';

  @override
  String get pdfDraft => 'Draf (belum dikeluarkan)';

  @override
  String get pdfDueDate => 'Tarikh akhir';

  @override
  String get pdfDelivered => 'Dihantar';

  @override
  String get pdfTotalDue => 'Jumlah komisen';

  @override
  String get pdfNote =>
      'Komisen dikenakan atas barang dihantar sahaja, tanpa penghantaran; barang habis stok dan dibatalkan tidak dikenakan.';

  @override
  String get pdfCompanyNotConfigured => '(Butiran syarikat belum ditetapkan)';

  @override
  String get auditAdminOnly => 'Tindakan admin sahaja';

  @override
  String get auditActor => 'Siapa';

  @override
  String get auditActingFor => 'Bagi pihak';

  @override
  String get auditTable => 'Data';

  @override
  String get auditChanges => 'Perubahan';

  @override
  String get auditEmpty => 'Tiada rekod';

  @override
  String get loadMore => 'Muat lagi';

  @override
  String get auditActPlaceOrder => 'Buat pesanan';

  @override
  String get auditActSetCartItem => 'Ubah troli';

  @override
  String get auditActClearCart => 'Kosongkan troli';

  @override
  String get auditActSetOrderStatus => 'Ubah status pesanan';

  @override
  String get auditActConfirmOrder => 'Sahkan pesanan';

  @override
  String get auditActLogFollowup => 'Susulan';

  @override
  String get auditActCreateProduct => 'Cipta produk';

  @override
  String get auditActUpdateProduct => 'Ubah produk';

  @override
  String get auditActWholesalerStatus => 'Kelulusan / penggantungan';

  @override
  String get auditActCommissionRate => 'Ubah kadar komisen';

  @override
  String get auditActWholesalerFounding => 'Ahli pengasas';

  @override
  String get auditActWhatsappOptIn => 'Persetujuan WhatsApp';

  @override
  String get auditActExtendTrial => 'Lanjut percubaan';

  @override
  String get auditActMarkPaid => 'Tandakan langganan dibayar';

  @override
  String get auditActCancelSubscription => 'Batal langganan';

  @override
  String get auditActSubscriptionFounding => 'Harga pengasas';

  @override
  String get auditActGenerateInvoices => 'Jana invois';

  @override
  String get auditActIssueInvoice => 'Keluarkan invois';

  @override
  String get auditActInvoicePaid => 'Invois dibayar';

  @override
  String get auditActInsert => 'Tambah';

  @override
  String get auditActUpdate => 'Ubah';

  @override
  String get auditActDelete => 'Padam';

  @override
  String get navWhatsappOrders => 'Pesanan WhatsApp';

  @override
  String get waOrdersHint =>
      'Pesanan yang kedai hantar melalui WhatsApp (teks atau suara). AI sediakan draf dahulu: semak, betulkan, kemudian buat pesanan untuk kedai. Yang ditolak akan dibalas dengan sebab melalui WhatsApp (dalam 24 jam).';

  @override
  String get waOrdersEmpty => 'Tiada pesanan WhatsApp untuk diuruskan sekarang';

  @override
  String get waVoice => 'Suara';

  @override
  String get waText => 'Teks';

  @override
  String waItems(int count) {
    return '$count barang';
  }

  @override
  String waUnmatchedCount(int count) {
    return '$count tidak dipadankan';
  }

  @override
  String get waWindowOpen => 'Dalam 24 jam: boleh balas di WhatsApp';

  @override
  String get waWindowClosed => 'Lebih 24 jam: tidak boleh balas di WhatsApp, sila telefon';

  @override
  String waAiFailed(String code) {
    return 'AI tidak dapat memproses ($code). Sila dengar / baca sendiri';
  }

  @override
  String get waMessage => 'Kata kedai';

  @override
  String get waNoTranscript => '(Tiada teks: nota suara tidak ditranskripsi)';

  @override
  String get waUnmatched => 'Frasa yang tidak dipadankan dengan barang';

  @override
  String get waAddItem => 'Tambah barang';

  @override
  String get waRemove => 'Buang';

  @override
  String waSubmit(String total) {
    return 'Buat pesanan untuk kedai $total';
  }

  @override
  String get waReject => 'Tolak';

  @override
  String get waRejectReason => 'Sebab (dihantar kepada kedai melalui WhatsApp)';

  @override
  String waSubmitted(String orders) {
    return 'Pesanan dibuat: $orders';
  }

  @override
  String get waRejectedDone => 'Ditolak. Balasan WhatsApp telah dijadualkan';

  @override
  String get waDone => 'Ini sudah diuruskan';

  @override
  String get waSearchProduct => 'Cari nama barang';

  @override
  String get waNoProducts => 'Tiada barang dijumpai';

  @override
  String get waEmptyDraft => 'Draf belum ada barang';

  @override
  String get waNotFound => 'Draf ini tidak dijumpai';

  @override
  String waSaid(String said) {
    return 'Kedai sebut: \"$said\"';
  }

  @override
  String get waUnsure => 'AI kurang pasti';

  @override
  String get waTagAiFailed => 'AI gagal';

  @override
  String get waTagWindowClosed => 'Lebih 24 jam';

  @override
  String get auditActSaveDraft => 'Ubah draf pesanan';

  @override
  String get auditActSubmitDraft => 'Buat pesanan WhatsApp untuk kedai';

  @override
  String get auditActRejectDraft => 'Tolak draf pesanan';

  @override
  String get navPayments => 'Bayaran';

  @override
  String get paymentsEmpty => 'Tiada bayaran';

  @override
  String get payReviewOnly => 'Perlu tindakan sahaja';

  @override
  String payNeedsReview(String reason) {
    return 'Perlu tindakan: $reason';
  }

  @override
  String get purposeSubscription => 'Langganan pembeli';

  @override
  String get purposeListingFee => 'Yuran penyenaraian pengasas';

  @override
  String get purposeCommission => 'Invois komisen';

  @override
  String get payStatusPending => 'Menunggu';

  @override
  String get payStatusPaid => 'Dibayar';

  @override
  String get payStatusFailed => 'Gagal';

  @override
  String get payStatusRefunded => 'Dipulangkan';

  @override
  String get colMethod => 'Kaedah';

  @override
  String get colReference => 'Rujukan gateway';

  @override
  String get colTime => 'Masa';

  @override
  String monthsN(int n) {
    return '$n bulan';
  }

  @override
  String get payLink => 'Pautan bayaran';

  @override
  String get payLinkTitle => 'Pautan bayaran';

  @override
  String payLinkAmount(String amount) {
    return 'Jumlah $amount (dikira oleh pelayan)';
  }

  @override
  String get payLinkHelp =>
      'Salin dan hantar melalui WhatsApp. Mereka boleh bayar dengan FPX, DuitNow atau e-dompet; bayaran direkod secara automatik.';

  @override
  String get payLinkCopy => 'Salin';

  @override
  String get payLinkCopied => 'Disalin';

  @override
  String get wsListingFeePaid => 'Yuran penyenaraian dibayar';

  @override
  String get wsListingFeeUnpaid => 'Yuran penyenaraian belum dibayar';

  @override
  String get wsMarkListingFee => 'Tanda yuran penyenaraian dibayar';

  @override
  String get errNothingDue => 'Sudah dibayar';

  @override
  String get errPaymentNotConfigured => 'Gateway bayaran belum ditetapkan (HITPAY_API_KEY)';

  @override
  String get errGateway => 'Gateway bayaran tidak tersedia, sila cuba lagi nanti';

  @override
  String get errTooManyPayments => 'Terlalu banyak pautan bayaran, sila tunggu';

  @override
  String get navCompanies => 'Syarikat';

  @override
  String get coHint =>
      'Akaun syarikat (hotel, kilang, rangkaian…): pelan, percubaan, invois, penggantungan. Syarikat urus cawangan dan ahli sendiri di web perolehan.';

  @override
  String get coSearchHint => 'Nama syarikat, SSM atau telefon';

  @override
  String get coEmpty => 'Tiada syarikat';

  @override
  String get coLegalName => 'Nama berdaftar';

  @override
  String get coType => 'Jenis';

  @override
  String get coSitesLabel => 'Cawangan';

  @override
  String get coMembersLabel => 'Ahli';

  @override
  String get coAccessUntil => 'Akses hingga';

  @override
  String get coOpenInvoices => 'Invois belum bayar';

  @override
  String get coSuspend => 'Gantung';

  @override
  String get coSuspendHelp =>
      'Semasa digantung, ahli tidak boleh membuat perubahan dan cawangan tidak nampak harga. Sebab disimpan dalam log audit.';

  @override
  String get coRestore => 'Pulihkan';

  @override
  String coSuspendedBecause(String note) {
    return 'Digantung: $note';
  }

  @override
  String coMarkPaidHelp(String amount) {
    return 'Guna ini selepas syarikat memindahkan $amount kepada kami. Langganan dilanjutkan satu tempoh, sama seperti bayaran dalam talian.';
  }

  @override
  String get coSectionProfile => 'Profil';

  @override
  String get coTin => 'No. cukai (TIN)';

  @override
  String get coBillingAddress => 'Alamat bil';

  @override
  String get coRegion => 'Wilayah';

  @override
  String get coSectionSubscription => 'Pelan';

  @override
  String get coCustomPrice => 'Harga khas';

  @override
  String get coLockedPrice => 'Harga terkunci';

  @override
  String get coGraceUntil => 'Tangguh hingga';

  @override
  String get coPendingPlan => 'Tempoh seterusnya';

  @override
  String get coLimits => 'Had';

  @override
  String coLimitsValue(String sites, String users) {
    return '$sites cawangan / $users pengguna';
  }

  @override
  String get coSetPlan => 'Tetapkan pelan';

  @override
  String get coSetPlanHelp =>
      'Berkuat kuasa sekarang (Perusahaan hanya boleh ditetapkan di sini). Invois belum bayar dibatalkan dan dikeluarkan semula pada harga baharu.';

  @override
  String get coPlan => 'Pelan';

  @override
  String get coCustomPriceLabel => 'Harga khas RM setempoh (kosong = harga semasa; wajib untuk Perusahaan)';

  @override
  String get coInvoiceIssued => 'Invois dikeluarkan';

  @override
  String get coSectionSites => 'Cawangan / tapak';

  @override
  String get coNoSites => 'Belum ada cawangan';

  @override
  String get coCostCenter => 'Pusat kos';

  @override
  String get coArchived => 'Diarkibkan';

  @override
  String get coSectionMembers => 'Ahli';

  @override
  String get coAllSites => 'Semua cawangan';

  @override
  String get coInactive => 'Tidak aktif';

  @override
  String get coInvites => 'Jemputan belum diterima';

  @override
  String get coInviteExpired => 'Tamat tempoh';

  @override
  String coInviteUntil(String time) {
    return 'Sah hingga $time';
  }

  @override
  String get coSectionInvoices => 'Invois pelan';

  @override
  String coDue(String date) {
    return 'Tarikh akhir $date';
  }

  @override
  String get coSectionPayments => 'Bayaran';

  @override
  String get coNoPayments => 'Belum ada bayaran';

  @override
  String get coStatusActive => 'Aktif';

  @override
  String get coStatusSuspended => 'Digantung';

  @override
  String get coTypeCorporate => 'Korporat';

  @override
  String get coTypeFactory => 'Kilang';

  @override
  String get coTypeHotel => 'Hotel';

  @override
  String get coTypeRestaurantChain => 'Rangkaian restoran';

  @override
  String get coTypeGlc => 'GLC';

  @override
  String get coTypeOther => 'Lain-lain';

  @override
  String get coRoleAdmin => 'Pentadbir';

  @override
  String get coRoleApprover => 'Pelulus';

  @override
  String get coRoleFinance => 'Kewangan';

  @override
  String get coRoleRequester => 'Pemohon';

  @override
  String get coCycleMonthly => 'Bulanan';

  @override
  String get coCycleAnnual => 'Tahunan';

  @override
  String get coPlanTrial => 'Percubaan';

  @override
  String get coPlanStarter => 'Permulaan';

  @override
  String get coPlanPro => 'Pro';

  @override
  String get coPlanEnterprise => 'Perusahaan';

  @override
  String get purposeCompanyPlan => 'Pelan syarikat';

  @override
  String get errCompanyNotFound => 'Syarikat tidak dijumpai';

  @override
  String get auditActCompanyStatus => 'Syarikat digantung / dipulihkan';

  @override
  String get auditActCompanyPlan => 'Pelan syarikat ditetapkan';

  @override
  String get auditActCompanyTrial => 'Percubaan syarikat dilanjutkan';

  @override
  String get auditActCompanyInvoice => 'Invois syarikat dikeluarkan';

  @override
  String get auditActCompanyInvoicePaid => 'Invois syarikat dibayar';

  @override
  String get auditActCompanyEdit => 'Profil / cawangan / ahli syarikat diubah';
}
