// 测试里自己做的小 Excel（SheetJS 写出来）。
// @deno-types="https://cdn.sheetjs.com/xlsx-0.20.3/package/types/index.d.ts"
import * as XLSX from "xlsx";

/** 测试里自己做一个小 Excel */
export function makeWorkbook(bookType: "xlsx" | "biff8", hidden = true): Uint8Array {
  const ws = XLSX.utils.aoa_to_sheet([
    ["新山包装批发 JB Packaging Supply"],
    [],
    ["No", "货品 Item", "Unit", "Harga (RM)", "MOQ"],
    [1, "16安士 PP杯 95口径", "箱", 85.5, "5 ctn"],
    [2, "95 平盖", "ctn", 40, ""],
    [3, "Straw 6mm / 8mm", "pkt", "RM3.50 / RM4.00", ""],
  ]);
  ws["D4"].z = '"RM"#,##0.00';
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, "Harga");
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([["secret cost price", 1]]), "Kos");
  if (hidden) wb.Workbook = { Sheets: [{ Hidden: 0 }, { Hidden: 1 }] };
  return new Uint8Array(XLSX.write(wb, { type: "array", bookType }) as ArrayBuffer);
}
