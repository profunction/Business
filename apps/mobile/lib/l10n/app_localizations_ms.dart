// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malay (`ms`).
class L10nMs extends L10n {
  L10nMs([String locale = 'ms']) : super(locale);

  @override
  String get appTitle => 'Borong JB';

  @override
  String get retry => 'Cuba lagi';

  @override
  String get cancel => 'Batal';

  @override
  String get ok => 'OK';

  @override
  String get save => 'Simpan';

  @override
  String get next => 'Seterusnya';

  @override
  String get back => 'Kembali';

  @override
  String get optional => 'Pilihan';

  @override
  String get errNetwork => 'Tiada sambungan internet. Sila semak dan cuba lagi.';

  @override
  String get errUnknown => 'Ada masalah. Sila cuba lagi.';

  @override
  String get errAuth => 'Kod salah atau sudah tamat tempoh. Sila cuba lagi.';

  @override
  String get errNotAllowed => 'Anda tidak dibenarkan buat ini.';

  @override
  String get errPriceChanged => 'Pemborong baru tukar harga. Sila semak jumlah sekali lagi.';

  @override
  String get errCartHasProblems => 'Ada masalah dalam troli. Sila betulkan bahagian merah dahulu.';

  @override
  String get errCartEmpty => 'Troli anda kosong.';

  @override
  String get errUnlockCooldown => 'Anda belum boleh tukar pemborong yang dipilih.';

  @override
  String get errTooManyWholesalers => 'Terlalu banyak pemborong untuk pelan percuma.';

  @override
  String get errWholesalerNotAvailable => 'Pemborong ini tidak menghantar ke kawasan anda sekarang.';

  @override
  String get errInvalidTransition => 'Pesanan ini sudah berubah. Sila muat semula.';

  @override
  String get errOrderNotDelivered => 'Anda boleh beri nilai selepas barang sampai.';

  @override
  String get errNoPreviousOrder => 'Anda belum pernah buat pesanan.';

  @override
  String get languagePageTitle => '请选择语言 · Choose language · Pilih bahasa';

  @override
  String get loginTitle => 'Log masuk dengan nombor telefon';

  @override
  String get loginSubtitle => 'Kami akan hantar kod ke telefon anda';

  @override
  String get phoneLabel => 'Nombor telefon';

  @override
  String get phoneInvalid => 'Itu bukan nombor telefon bimbit. Sila semak semula.';

  @override
  String get sendCode => 'Hantar kod';

  @override
  String get otpTitle => 'Masukkan kod';

  @override
  String otpSentTo(String phone) {
    return 'Kod telah dihantar ke $phone';
  }

  @override
  String get otpLogin => 'Log masuk';

  @override
  String get otpResend => 'Hantar semula';

  @override
  String otpResendIn(int seconds) {
    return 'Hantar semula dalam $seconds saat';
  }

  @override
  String get changePhone => 'Tukar nombor';

  @override
  String get registerTitle => 'Daftar kedai anda';

  @override
  String get shopNameQuestion => 'Apakah nama kedai anda?';

  @override
  String get shopNameHint => 'cth. Restoran Ali';

  @override
  String get shopTypeQuestion => 'Kedai anda jenis apa?';

  @override
  String get shopTypeRestaurant => 'Restoran';

  @override
  String get shopTypeDrinkStall => 'Gerai minuman';

  @override
  String get shopTypeGrocery => 'Kedai runcit';

  @override
  String get shopTypeOther => 'Lain-lain';

  @override
  String get zoneQuestion => 'Kedai anda di kawasan mana?';

  @override
  String get addressQuestion => 'Alamat kedai (untuk penghantaran)';

  @override
  String get addressHint => 'cth. 12, Jalan Molek 1/2, Taman Molek';

  @override
  String get registerFinish => 'Mula';

  @override
  String get homeReorder => 'Sama macam lepas';

  @override
  String homeReorderLast(String date, String total) {
    return 'Kali lepas: $date, $total';
  }

  @override
  String get homeShop => 'Beli barang';

  @override
  String get homeOrders => 'Pesanan saya';

  @override
  String homeActiveOrders(int count) {
    return '$count sedang diproses';
  }

  @override
  String homeCart(int count) {
    return 'Troli ($count barang)';
  }

  @override
  String trialBanner(int days) {
    return 'Percubaan percuma tinggal $days hari. Semua harga boleh dilihat.';
  }

  @override
  String freeBanner(int count) {
    return 'Pelan percuma: pilih $count pemborong untuk lihat harga';
  }

  @override
  String get chooseWholesalers => 'Pilih pemborong';

  @override
  String get settings => 'Tetapan';

  @override
  String get browseTitle => 'Beli barang';

  @override
  String get browseByProduct => 'Ikut barang';

  @override
  String get browseByWholesaler => 'Ikut pemborong';

  @override
  String get searchHint => 'Cari, cth. cawan';

  @override
  String get noResults => 'Tiada hasil';

  @override
  String categoryItemCount(int count) {
    return '$count barang';
  }

  @override
  String sellerCount(int count) {
    return '$count penjual';
  }

  @override
  String cheapestPerUnit(String sen) {
    return 'Dari $sen sen sebiji';
  }

  @override
  String get compareTitle => 'Banding harga';

  @override
  String perUnit(String sen) {
    return '$sen sen sebiji';
  }

  @override
  String pricePerSellUnit(String price, String unit) {
    return '$price / $unit';
  }

  @override
  String packQty(String unit, int qty) {
    return '$qty biji setiap $unit';
  }

  @override
  String get priceLocked => 'Harga tersembunyi';

  @override
  String rating(String avg, int count) {
    return '$avg ($count ulasan)';
  }

  @override
  String get noRatings => 'Belum ada ulasan';

  @override
  String leadTime(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Sampai dalam $days hari',
      one: 'Sampai esok',
      zero: 'Sampai hari ini',
    );
    return '$_temp0';
  }

  @override
  String minOrderQty(int qty, String unit) {
    return 'Minimum $qty $unit';
  }

  @override
  String shippingFee(String fee) {
    return 'Penghantaran $fee';
  }

  @override
  String freeShippingOver(String amount) {
    return 'Percuma melebihi $amount';
  }

  @override
  String minOrderAmount(String amount) {
    return 'Pesanan minimum $amount';
  }

  @override
  String get outOfStock => 'Habis stok';

  @override
  String get lowStock => 'Stok rendah';

  @override
  String get founding => 'Ahli pengasas';

  @override
  String get addToCart => 'Masuk troli';

  @override
  String inCart(int qty) {
    return '$qty dalam troli';
  }

  @override
  String get updateCart => 'Kemas kini troli';

  @override
  String get removeFromCart => 'Buang';

  @override
  String get addedToCart => 'Sudah masuk troli';

  @override
  String get lockedHint => 'Pelan percuma hanya tunjuk harga pemborong yang anda pilih';

  @override
  String get chooseThisWholesaler => 'Tambah pemborong ini ke senarai percuma';

  @override
  String get freeSlotsFull => 'Senarai percuma penuh. Pergi ke \"Pilih pemborong\" untuk tukar.';

  @override
  String get unitCarton => 'karton';

  @override
  String get unitPack => 'paket';

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
  String productCount(int count) {
    return '$count produk';
  }

  @override
  String deliveryDays(String days) {
    return 'Hantar: $days';
  }

  @override
  String get weekdayShort1 => 'Isn';

  @override
  String get weekdayShort2 => 'Sel';

  @override
  String get weekdayShort3 => 'Rab';

  @override
  String get weekdayShort4 => 'Kha';

  @override
  String get weekdayShort5 => 'Jum';

  @override
  String get weekdayShort6 => 'Sab';

  @override
  String get weekdayShort7 => 'Ahd';

  @override
  String get paymentCod => 'Tunai semasa terima';

  @override
  String get paymentTransfer => 'Pindahan bank';

  @override
  String get paymentCredit => 'Kredit bulanan';

  @override
  String get cartTitle => 'Troli';

  @override
  String get cartEmpty => 'Troli anda kosong';

  @override
  String get goodsSubtotal => 'Barang';

  @override
  String get shipping => 'Penghantaran';

  @override
  String get freeShipping => 'Percuma';

  @override
  String get total => 'Jumlah';

  @override
  String shortOfFreeShipping(String amount) {
    return 'Tambah $amount lagi untuk penghantaran percuma';
  }

  @override
  String shortOfMinOrder(String amount) {
    return 'Tambah $amount lagi untuk capai pesanan minimum';
  }

  @override
  String expectedDelivery(String date) {
    return 'Dijangka sampai $date';
  }

  @override
  String get problemProductUnavailable => 'Barang ini tidak dijual lagi. Sila buang.';

  @override
  String get problemNotDelivering => 'Pemborong ini tidak menghantar ke kawasan anda sekarang';

  @override
  String get problemWholesalerLocked => 'Harga pemborong ini tersembunyi dalam pelan percuma, jadi tidak boleh pesan';

  @override
  String get problemOutOfStock => 'Habis stok. Sila buang.';

  @override
  String problemBelowMinQty(int qty) {
    return 'Minimum $qty';
  }

  @override
  String get goToConfirm => 'Seterusnya: semak pesanan';

  @override
  String get fixProblemsFirst => 'Sila betulkan masalah berwarna merah dahulu';

  @override
  String get confirmTitle => 'Semak pesanan';

  @override
  String ordersWillSplit(int count) {
    return 'Ini akan jadi $count pesanan. Setiap pemborong hantar sendiri.';
  }

  @override
  String get noteLabel => 'Nota';

  @override
  String placeOrder(String total) {
    return 'Buat pesanan $total';
  }

  @override
  String get priceChangedTitle => 'Harga berubah';

  @override
  String get reorderPriceChanges => 'Harga barang ini berubah:';

  @override
  String get reorderSkipped => 'Barang ini tiada lagi dan telah dibuang:';

  @override
  String priceChangeLine(String name, String oldPrice, String newPrice) {
    return '$name: $oldPrice → $newPrice';
  }

  @override
  String get orderPlacedTitle => 'Pesanan berjaya!';

  @override
  String get orderPlacedBody => 'Kami akan maklumkan apabila pemborong sahkan';

  @override
  String get viewOrders => 'Lihat pesanan saya';

  @override
  String get backHome => 'Kembali ke laman utama';

  @override
  String get ordersTitle => 'Pesanan saya';

  @override
  String get noOrders => 'Belum ada pesanan';

  @override
  String get statusPending => 'Menunggu';

  @override
  String get statusConfirmed => 'Disahkan';

  @override
  String get statusOutOfStock => 'Habis stok';

  @override
  String get statusDelivering => 'Dalam penghantaran';

  @override
  String get statusDelivered => 'Sudah sampai';

  @override
  String get statusCancelled => 'Dibatalkan';

  @override
  String itemCount(int count) {
    return '$count barang';
  }

  @override
  String outOfStockCount(int count) {
    return '$count habis stok';
  }

  @override
  String orderTitle(String orderNo) {
    return 'Pesanan $orderNo';
  }

  @override
  String orderedAt(String date) {
    return 'Dipesan: $date';
  }

  @override
  String get callWholesaler => 'Telefon pemborong';

  @override
  String get markReceived => 'Sudah terima';

  @override
  String get markReceivedConfirm => 'Sahkan anda sudah terima barang?';

  @override
  String get cancelOrder => 'Batalkan pesanan';

  @override
  String get cancelOrderConfirm => 'Batalkan pesanan ini?';

  @override
  String get cancelReasonHint => 'Sebab (pilihan)';

  @override
  String cancelledReason(String reason) {
    return 'Sebab: $reason';
  }

  @override
  String get writeReview => 'Nilai pemborong ini';

  @override
  String get editReview => 'Ubah ulasan';

  @override
  String get yourReview => 'Ulasan anda';

  @override
  String get itemOutOfStockLabel => 'Habis stok (tidak dicaj)';

  @override
  String paymentTerms(String terms) {
    return 'Bayaran: $terms';
  }

  @override
  String get reviewTitle => 'Beri nilai';

  @override
  String get reviewQuestion => 'Bagaimana pemborong ini?';

  @override
  String get tagOnTime => 'Tepat masa';

  @override
  String get tagGoodQuality => 'Kualiti baik';

  @override
  String get tagWellPacked => 'Bungkusan kemas';

  @override
  String get tagGoodPrice => 'Harga berpatutan';

  @override
  String get tagFriendly => 'Mesra';

  @override
  String get tagLate => 'Lewat';

  @override
  String get tagWrongItems => 'Barang salah';

  @override
  String get tagDamaged => 'Rosak';

  @override
  String get tagMissingItems => 'Barang tak cukup';

  @override
  String get reviewCommentHint => 'Ada lagi? (pilihan)';

  @override
  String get submitReview => 'Hantar';

  @override
  String get reviewThanks => 'Terima kasih atas ulasan anda!';

  @override
  String get freeWholesalersTitle => 'Akses harga percuma';

  @override
  String freeWholesalersBody(int count) {
    return 'Dalam pelan percuma, anda boleh pilih $count pemborong. Anda nampak harga penuh dan boleh pesan daripada mereka.';
  }

  @override
  String freeWholesalersCooldown(String date) {
    return 'Anda boleh tukar pemborong yang dipilih pada $date';
  }

  @override
  String selectedCount(int selected, int max) {
    return 'Dipilih $selected/$max';
  }

  @override
  String get fullAccessNoNeed => 'Anda boleh lihat semua harga sekarang. Tidak perlu pilih.';

  @override
  String get saved => 'Sudah disimpan';

  @override
  String get settingsTitle => 'Tetapan';

  @override
  String get language => 'Bahasa';

  @override
  String get myShop => 'Kedai saya';

  @override
  String get subscription => 'Langganan';

  @override
  String subTrial(String date) {
    return 'Percubaan percuma hingga $date';
  }

  @override
  String subActive(String date) {
    return 'Sudah melanggan. Pembaharuan seterusnya $date';
  }

  @override
  String subPastDue(String date) {
    return 'Langganan sudah tamat. Perbaharui sebelum $date untuk kekalkan harga anda.';
  }

  @override
  String get subFree => 'Pelan percuma';

  @override
  String lockedPrice(String price) {
    return 'Yuran bulanan anda dikunci pada $price selagi anda terus memperbaharui';
  }

  @override
  String get subscribeComingSoon => 'Pelan berbayar akan datang tidak lama lagi';

  @override
  String get logout => 'Log keluar';

  @override
  String get logoutConfirm => 'Log keluar sekarang?';

  @override
  String get sellerComingSoon => 'Ciri untuk pemborong sedang dibina dan akan siap tidak lama lagi';

  @override
  String get sellerPending => 'Maklumat pemborong anda sedang menunggu semakan';

  @override
  String get adminUseWeb => 'Khidmat pelanggan: sila guna laman admin';

  @override
  String get pushChannelName => 'Notifikasi pesanan';

  @override
  String get pushChannelDescription => 'Pesanan baharu, kemas kini pesanan dan ringkasan penghantaran harian';

  @override
  String get pushAskTitle => 'Hidupkan notifikasi?';

  @override
  String get pushAskSellerBody =>
      'Telefon anda akan berbunyi bila ada pesanan baharu, jadi tiada pesanan yang terlepas.';

  @override
  String get pushAskBuyerBody =>
      'Kami akan maklumkan sebaik sahaja pemborong mengesahkan, kehabisan stok atau menghantar pesanan anda.';

  @override
  String get pushAskAllow => 'Hidupkan';

  @override
  String get pushAskLater => 'Nanti dulu';

  @override
  String get pushDenied => 'Notifikasi tidak dihidupkan. Anda boleh hidupkan di Tetapan > Notifikasi telefon anda.';

  @override
  String get sellerErrUnsupportedFile =>
      'Fail jenis ini tidak dapat dibaca. Sila ambil gambar, atau pilih fail Excel, PDF atau CSV.';

  @override
  String get sellerErrFileTooLarge => 'Fail terlalu besar (maksimum 10 MB).';

  @override
  String get sellerErrAiFailed =>
      'AI tidak dapat membaca senarai harga ini. Sila ambil gambar yang lebih jelas dan cuba lagi.';

  @override
  String get sellerErrImportTimeout => 'AI masih membaca. Sila semak semula dalam beberapa minit.';

  @override
  String get sellerErrImportDone => 'Senarai harga ini sudah diproses.';

  @override
  String sellerErrRowIncomplete(int row) {
    return 'Baris $row tiada nama, unit, saiz pek atau harga.';
  }

  @override
  String sellerErrRowInvalidProduct(int row) {
    return 'Baris $row dipadankan dengan produk yang salah. Sila pilih semula.';
  }

  @override
  String sellerErrDuplicateProduct(int row) {
    return 'Baris $row mengemas kini produk yang sama dengan baris lain. Sila tukar salah satu.';
  }

  @override
  String get sellerErrItemNotInOrder => 'Barang itu tiada dalam pesanan ini. Sila buka semula pesanan.';

  @override
  String get sellerErrNotFound => 'Tidak dijumpai. Mungkin sudah dibuang.';

  @override
  String sellerHomeNewOrders(int count) {
    return 'Pesanan baharu ($count)';
  }

  @override
  String get sellerNoNewOrders => 'Tiada pesanan baharu';

  @override
  String sellerOldestWaiting(String duration) {
    return 'Yang paling lama sudah menunggu $duration';
  }

  @override
  String sellerWaiting(String duration) {
    return 'Menunggu $duration';
  }

  @override
  String sellerMinutes(int count) {
    return '$count minit';
  }

  @override
  String sellerHours(int count) {
    return '$count jam';
  }

  @override
  String sellerDays(int count) {
    return '$count hari';
  }

  @override
  String sellerHomeToday(int count) {
    return 'Hantar hari ini ($count)';
  }

  @override
  String sellerTodayTotal(String total) {
    return 'Jumlah $total';
  }

  @override
  String get sellerNothingToday => 'Tiada penghantaran hari ini';

  @override
  String get sellerHomeProducts => 'Produk & harga';

  @override
  String sellerProductsActive(int count) {
    return '$count dijual';
  }

  @override
  String sellerProductsOutOfStock(int count) {
    return '$count habis stok';
  }

  @override
  String sellerProductsLowStock(int count) {
    return '$count hampir habis';
  }

  @override
  String sellerProductsDraft(int count) {
    return '$count draf';
  }

  @override
  String get sellerHomeImport => 'Muat naik senarai harga';

  @override
  String get sellerImportNone => 'Ambil gambar atau pilih fail Excel. AI sediakan senarai produk anda.';

  @override
  String get sellerImportProcessing => 'AI sedang membaca senarai harga anda…';

  @override
  String get sellerImportReview => 'AI sudah siap. Semak dan mula jual.';

  @override
  String get sellerImportFailed => 'Yang lepas tidak dapat dibaca. Sila muat naik semula.';

  @override
  String sellerImportApplied(String date) {
    return 'Mula dijual pada $date';
  }

  @override
  String get sellerPendingBanner =>
      'Kami sedang menyemak maklumat anda. Pembeli belum nampak anda, tetapi anda boleh mula masukkan produk dan harga.';

  @override
  String get sellerSuspendedBanner =>
      'Akaun anda digantung, jadi pembeli tidak nampak anda sekarang. Sila hubungi khidmat pelanggan.';

  @override
  String get sellerOrdersTitle => 'Pesanan';

  @override
  String get sellerTabPending => 'Baharu';

  @override
  String get sellerTabToday => 'Hari ini';

  @override
  String get sellerTabAll => 'Semua';

  @override
  String sellerTabWithCount(String label, int count) {
    return '$label ($count)';
  }

  @override
  String sellerTodayCount(int count, String total) {
    return '$count pesanan, jumlah $total';
  }

  @override
  String get sellerOpenSummary => 'Senarai hantar (ambil barang, cetak)';

  @override
  String sellerDeliverOn(String date) {
    return 'Hantar: $date';
  }

  @override
  String sellerBuyerNote(String note) {
    return 'Nota pembeli: $note';
  }

  @override
  String get sellerCall => 'Telefon';

  @override
  String get sellerWhatsapp => 'WhatsApp';

  @override
  String sellerWhatsappHello(String orderNo) {
    return 'Hai, tentang pesanan anda $orderNo:';
  }

  @override
  String get sellerCannotOpen => 'Tidak dapat dibuka. Adakah aplikasi itu ada di telefon ini?';

  @override
  String sellerContact(String name) {
    return 'Hubungi: $name';
  }

  @override
  String get sellerConfirm => 'Sahkan';

  @override
  String get sellerOutOfStock => 'Habis stok';

  @override
  String get sellerChecklistTitle => 'Ada barang yang habis stok?';

  @override
  String get sellerChecklistHint =>
      'Tandakan barang yang tiada. Barang itu tidak dicaj. Kalau semua ada, terus sahkan.';

  @override
  String get sellerConfirmAllInStock => 'Semua ada, sahkan';

  @override
  String sellerConfirmWithOos(int count) {
    return 'Sahkan ($count habis stok)';
  }

  @override
  String get sellerConfirmAllOos => 'Semua habis stok';

  @override
  String get sellerOosConfirmTitle => 'Seluruh pesanan habis stok?';

  @override
  String get sellerOosConfirmBody => 'Pembeli akan dimaklumkan dan pesanan ini tidak akan dihantar.';

  @override
  String get sellerOosConfirmButton => 'Tanda habis stok';

  @override
  String get sellerConfirmedMsg => 'Disahkan. Pembeli akan dimaklumkan.';

  @override
  String get sellerOosMsg => 'Ditanda habis stok. Pembeli akan dimaklumkan.';

  @override
  String get sellerStartDelivery => 'Mula hantar';

  @override
  String get sellerMarkDelivered => 'Sudah dihantar';

  @override
  String get sellerDeliveredConfirm => 'Pesanan sudah sampai?';

  @override
  String get sellerDeliveringMsg => 'Dalam perjalanan. Pembeli akan dimaklumkan.';

  @override
  String get sellerDeliveredMsg => 'Sudah dihantar. Terima kasih!';

  @override
  String get sellerMyBusiness => 'Perniagaan saya';

  @override
  String get sellerNotifyTitle => 'Bagaimana kami maklumkan pesanan baharu?';

  @override
  String get sellerNotifyAuto => 'Automatik (disyorkan)';

  @override
  String get sellerNotifyAutoHint => 'Notifikasi aplikasi jika aplikasi ada di telefon, jika tidak WhatsApp';

  @override
  String get sellerNotifyPush => 'Notifikasi aplikasi';

  @override
  String get sellerNotifyWhatsapp => 'WhatsApp';

  @override
  String sellerNotifyWhatsappTo(String phone) {
    return 'Dihantar ke $phone';
  }

  @override
  String get sellerNotifyNoWhatsapp => 'Belum ada nombor WhatsApp. Khidmat pelanggan boleh tambahkan.';

  @override
  String get sellerWhatsappOptIn => 'Terima pesanan melalui WhatsApp';

  @override
  String get sellerWhatsappOptInHint => 'Jika ditutup, kami tidak akan hantar WhatsApp kepada anda';

  @override
  String get sellerNotifyOwnerOnly => 'Hanya pemilik boleh ubah. Khidmat pelanggan juga boleh tolong ubah.';

  @override
  String get pushSettingsTitle => 'Notifikasi di telefon ini';

  @override
  String get pushStatusOn => 'Dihidupkan. Telefon akan berbunyi untuk pesanan baharu.';

  @override
  String get pushStatusOff => 'Notifikasi belum dihidupkan';

  @override
  String get pushNotSupported =>
      'Telefon ini tidak boleh terima notifikasi aplikasi. Anda boleh terima pesanan melalui WhatsApp.';

  @override
  String get sellerSummaryTitle => 'Senarai hantar';

  @override
  String sellerSummaryHeading(String date) {
    return 'Senarai hantar $date';
  }

  @override
  String get sellerSummaryPrevDay => 'Hari sebelumnya';

  @override
  String get sellerSummaryNextDay => 'Hari berikutnya';

  @override
  String sellerSummaryPending(int count) {
    return '$count pesanan belum disahkan';
  }

  @override
  String get sellerSummaryGoConfirm => 'Sahkan';

  @override
  String get sellerSummaryPicking => 'Senarai ambil barang';

  @override
  String get sellerSummaryPickingHint => 'Semua pesanan dicampur. Barang habis stok tidak dikira.';

  @override
  String sellerSummaryQty(int qty, String unit) {
    return '$qty $unit';
  }

  @override
  String get sellerSummaryEmpty => 'Tiada penghantaran pada hari ini';

  @override
  String get sellerSummaryOrders => 'Pesanan (ikut kawasan, kemudian kedai)';

  @override
  String get sellerSummaryOtherArea => 'Kawasan lain';

  @override
  String get sellerSummaryPrint => 'Cetak';

  @override
  String get sellerSummaryShare => 'Kongsi dengan pemandu';

  @override
  String sellerSummaryPhone(String phone) {
    return 'Telefon: $phone';
  }

  @override
  String sellerSummaryAddress(String address) {
    return 'Alamat: $address';
  }

  @override
  String get sellerSummaryOosMark => '(habis stok)';

  @override
  String get sellerSummarySignature => 'Diterima oleh:';

  @override
  String sellerSummaryPage(int page, int total) {
    return 'Halaman $page / $total';
  }

  @override
  String get sellerSummaryColItem => 'Barang';

  @override
  String get sellerSummaryColQty => 'Kuantiti';

  @override
  String get sellerSummaryColPack => 'Saiz pek';

  @override
  String get sellerSummaryPrintFailed => 'Tidak dapat mencetak. Sila cuba lagi.';

  @override
  String get sellerSummaryShareFailed => 'Tidak dapat berkongsi. Sila cuba lagi.';

  @override
  String get sellerProductsSearch => 'Cari barang';

  @override
  String get sellerFilterAll => 'Semua';

  @override
  String get sellerFilterOutOfStock => 'Habis stok';

  @override
  String get sellerFilterDraft => 'Draf';

  @override
  String get sellerStockIn => 'Ada stok';

  @override
  String get sellerStockLow => 'Stok rendah';

  @override
  String get sellerStockOut => 'Habis stok';

  @override
  String get sellerStatusDraft => 'Draf';

  @override
  String get sellerStatusArchived => 'Tidak dijual';

  @override
  String get sellerProductsEmpty =>
      'Belum ada barang. Tekan \"Tambah barang\", atau muat naik senarai harga dan biar AI buatkan.';

  @override
  String get sellerProductsNoMatch => 'Tiada barang yang sepadan';

  @override
  String get sellerAddProduct => 'Tambah barang';

  @override
  String get sellerEditProduct => 'Ubah barang';

  @override
  String get sellerFieldName => 'Nama barang';

  @override
  String get sellerFieldNameHint => 'cth. Cawan PP 16oz 95mm';

  @override
  String get sellerFieldUnit => 'Dijual dalam unit apa?';

  @override
  String sellerFieldPackQty(String unit) {
    return 'Berapa biji dalam 1 $unit?';
  }

  @override
  String sellerFieldPrice(String unit) {
    return 'Harga untuk 1 $unit';
  }

  @override
  String get sellerFieldPriceHint => 'cth. 12.50';

  @override
  String sellerFieldMinQty(String unit) {
    return 'Pesanan minimum ($unit)';
  }

  @override
  String get sellerFieldStock => 'Stok';

  @override
  String get sellerFieldStatus => 'Pembeli boleh nampak?';

  @override
  String get sellerOnSale => 'Dijual';

  @override
  String get sellerOffSale => 'Tidak dijual';

  @override
  String get sellerDraftHint => 'Ini draf, jadi pembeli belum nampak. Pilih \"Dijual\" dan simpan.';

  @override
  String get sellerOffSaleHint => 'Pembeli tidak akan nampak. Boleh dijual semula bila-bila masa.';

  @override
  String get sellerErrName => 'Sila tulis nama barang';

  @override
  String get sellerErrPrice => 'Sila tulis harga, cth. 12.50';

  @override
  String get sellerErrPackQty => 'Sekurang-kurangnya 1';

  @override
  String get sellerErrForm => 'Ada maklumat belum lengkap. Sila semak bahagian merah.';

  @override
  String get sellerPhoto => 'Gambar (tidak wajib)';

  @override
  String get sellerPhotoTake => 'Ambil gambar';

  @override
  String get sellerPhotoPick => 'Pilih gambar';

  @override
  String get sellerPhotoRemove => 'Buang gambar';

  @override
  String get sellerErrPhotoFile => 'Gambar mesti JPG, PNG atau WebP, maksimum 5 MB';

  @override
  String get sellerErrNoPermission => 'Sila benarkan aplikasi ini guna kamera dan gambar dalam Tetapan telefon';

  @override
  String get sellerImportIntro =>
      'Ambil gambar senarai harga, atau pilih fail Excel atau PDF. AI akan jadikannya barang, dan tiada yang dijual sehingga anda semak.';

  @override
  String get sellerImportCamera => 'Ambil gambar';

  @override
  String get sellerImportCameraHint => 'Ambil gambar senarai harga bercetak dengan jelas';

  @override
  String get sellerImportGallery => 'Pilih gambar';

  @override
  String get sellerImportGalleryHint => 'Gambar atau tangkapan skrin dalam telefon';

  @override
  String get sellerImportFile => 'Pilih fail (Excel, PDF)';

  @override
  String get sellerImportFileHint => 'Excel, PDF atau CSV, maksimum 10 MB';

  @override
  String get sellerImportUploading => 'Sedang memuat naik…';

  @override
  String get sellerImportUploaded => 'Sudah dimuat naik';

  @override
  String get sellerImportWaitHint =>
      'Biasanya ambil masa 1 hingga 3 minit. Anda boleh tinggalkan halaman ini. Skrin utama akan beritahu bila siap.';

  @override
  String get sellerImportStillReading => 'Masih membaca. Senarai harga yang panjang ambil masa lebih sikit…';

  @override
  String get sellerImportFailedTitle => 'AI tidak dapat membaca senarai harga ini';

  @override
  String get sellerImportRetry => 'Muat naik semula';

  @override
  String get sellerBackHome => 'Kembali ke halaman utama';

  @override
  String get sellerErrHeic =>
      'Ini gambar HEIC iPhone, yang AI tidak dapat baca. Tekan \"Pilih gambar\" dan pilih semula. Aplikasi akan tukar kepada JPG.';

  @override
  String get sellerImportErrRefused => 'AI tidak mahu membaca fail ini. Pastikan ia senarai harga dan cuba lagi.';

  @override
  String get sellerImportErrTruncated =>
      'Senarai harga terlalu panjang untuk AI habiskan. Sila bahagikan kepada beberapa gambar atau fail dan muat naik satu demi satu.';

  @override
  String get sellerReviewTitle => 'Semak senarai harga';

  @override
  String sellerReviewSummary(int total, int create, int update, int skip) {
    return '$total baris: $create baharu, $update kemas kini, $skip langkau';
  }

  @override
  String sellerReviewUnsure(int count) {
    return 'AI kurang pasti tentang $count baris. Sila semak yang kuning.';
  }

  @override
  String get sellerReviewHint =>
      'Untuk setiap baris, pilih Baharu, Kemas kini atau Langkau. Tekan Ubah untuk betulkan.';

  @override
  String sellerReviewRow(int row) {
    return 'Baris $row';
  }

  @override
  String get sellerReviewCheck => 'Sila semak';

  @override
  String get sellerReviewNoName => '(tiada nama)';

  @override
  String get sellerReviewNoPrice => 'Tiada harga';

  @override
  String sellerReviewRaw(String text) {
    return 'Asal: $text';
  }

  @override
  String sellerReviewMatched(String name) {
    return 'Akan kemas kini: $name';
  }

  @override
  String sellerReviewPriceNow(String price) {
    return 'sekarang $price';
  }

  @override
  String get sellerReviewNoMatch => 'Tiada barang anda yang sepadan. Boleh tambah sebagai baharu.';

  @override
  String get sellerReviewNoRows => 'AI tidak jumpa barang dalam senarai harga ini';

  @override
  String get sellerActionCreate => 'Baharu';

  @override
  String get sellerActionUpdate => 'Kemas kini';

  @override
  String get sellerActionSkip => 'Langkau';

  @override
  String sellerReviewMissing(String fields) {
    return 'Belum ada: $fields';
  }

  @override
  String get sellerMissingName => 'nama';

  @override
  String get sellerMissingUnit => 'unit';

  @override
  String get sellerMissingPack => 'saiz pek';

  @override
  String get sellerMissingPrice => 'harga';

  @override
  String get sellerMissingMatch => 'barang yang hendak dikemas kini';

  @override
  String get sellerReviewEdit => 'Ubah';

  @override
  String sellerReviewEditTitle(int row) {
    return 'Ubah baris $row';
  }

  @override
  String sellerApply(int count) {
    return 'Jual $count barang';
  }

  @override
  String sellerApplyDone(int created, int updated) {
    return 'Siap: $created ditambah, $updated dikemas kini';
  }

  @override
  String get sellerReviewApplied => 'Senarai harga ini sudah dijual';

  @override
  String get sellerReviewGoProducts => 'Lihat barang';

  @override
  String get sellerReviewWait => 'Tunggu AI';
}
