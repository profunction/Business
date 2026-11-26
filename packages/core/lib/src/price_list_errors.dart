// 价目表 AI（parse-price-list）的错误代码。App 每一个都要有自己的三语说明（apps/mobile 的 L10nX.priceListError）。
// supabase/functions/tests/error_codes_test.ts 会扫 Edge Function 的代码，确认这里一个都没漏。

/// 写进 price_list_imports.error_message 的代码：parse-price-list 写的、定时任务 fail_stuck_price_list_imports 写的
/// （AI_TIMEOUT、START_FAILED），还有 App 叫不到 parse-price-list 时自己写的（START_FAILED、NETWORK、AUTH）
const priceListImportErrorCodes = [
  // 文件问题
  'UNSUPPORTED_FILE',
  'FILE_TOO_LARGE',
  'EMPTY_FILE',
  'FILE_NOT_FOUND',
  'INVALID_FILE_PATH',
  'DOWNLOAD_FAILED',
  'SPREADSHEET_UNREADABLE',
  'EMPTY_SPREADSHEET',
  'TOO_MANY_ROWS',
  // AI 读不到
  'AI_REFUSED',
  'AI_TRUNCATED',
  'AI_INVALID_OUTPUT',
  'NO_PRODUCTS_FOUND',
  // AI、系统
  'AI_TIMEOUT',
  'AI_BUSY',
  'AI_UNAVAILABLE',
  'AI_FAILED',
  'AI_AUTH_FAILED',
  'AI_REQUEST_REJECTED',
  'AI_NOT_CONFIGURED',
  'DB_ERROR',
  'INTERNAL_ERROR',
  // App 自己写的
  'START_FAILED',
  'NETWORK',
  'AUTH',
];

/// parse-price-list 的 HTTP 回应 {"error": "CODE"}（见 supabase/functions/README.md）
const priceListHttpErrorCodes = [
  'INVALID_IMPORT_ID',
  'UNAUTHORIZED',
  'WHOLESALER_SUSPENDED',
  'IMPORT_NOT_FOUND',
  'IMPORT_NOT_PROCESSING',
  'IMPORT_ALREADY_RUNNING',
  'TOO_MANY_IMPORTS',
  'QUOTA_UNAVAILABLE',
  'CONFIG_MISSING',
  'DB_ERROR',
  'INTERNAL_ERROR',
  'METHOD_NOT_ALLOWED',
];
