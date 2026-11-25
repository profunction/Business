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
}
