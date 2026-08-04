/**
 * ===============================================
 * 展覽費用管理系統 - Google Apps Script 後端
 * ===============================================
 *
 * 部署步驟：
 * 1. 開一個新的 Google 試算表（空白的就可以，程式會自動建立分頁）
 * 2. 上方選單「擴充功能」>「Apps Script」
 * 3. 把這個檔案的全部內容貼進去，取代預設的程式碼，Ctrl+S 存檔
 * 4. 上方工具列選擇函式「setupSheets」，按執行 ▶（第一次執行會要求授權，
 *    選你的 Google 帳號 > 允許）
 * 5. 回到試算表確認多了「費用明細」「展覽總覽」兩個分頁
 * 6. 回 Apps Script，右上角「部署」>「新增部署作業」
 *    - 類型選「網頁應用程式」
 *    - 執行身份：我
 *    - 具有存取權的使用者：任何人
 *    - 按「部署」，複製產生的網址（結尾是 /exec）
 * 7. 把這個網址貼到 HTML 網頁裡右上角「設定」欄位（或請 Claude 幫你把網址
 *    直接寫死在 HTML 裡，同事就不用自己貼一次）
 *
 * 之後如果修改這份程式碼，要「部署」>「管理部署作業」> 編輯 > 新版本，
 * 網址才會套用最新程式碼。
 */

var SHEET_EXPENSE = '費用明細';
var SHEET_EXHIBITION = '展覽總覽';

// 費用類別 -> 費用類型（個人/公用）對照表，不要交給前端自己送，後端統一判斷才不會被繞過
var CATEGORY_TYPE = {
  '機票': '個人', '交通': '個人', '住宿': '個人', '餐費': '個人', '交際費': '個人', '人員': '個人',
  '攤位費': '公用', '裝潢': '公用', '設計': '公用', '印刷': '公用', '設備租借': '公用',
  '運輸': '公用', '保險': '公用', '行銷宣傳': '公用', '贈品': '公用', '雜支': '公用'
};
function getCategoryType(category) {
  return CATEGORY_TYPE[category] || '';
}

// 欄位固定不動：既有欄位保持原本的欄位編號，新欄位一律加在原本欄位「之後」，
// 這樣舊資料、既有公式、ID 對照欄位都不用搬動，舊資料的新欄位讀出來自然是空值。
var EXPENSE_HEADERS = [
  '展覽', '日期', '費用類別', '項目', '廠商', '幣別', '原幣金額',
  '匯率', '台幣金額', '付款方式', '發票', '備註', 'ID', '費用類型', '申請人'
];
var EXHIBITION_HEADERS = [
  '展覽名稱', '預算', '總成本', '差異', '備註', 'ID', '國家', '年度', '展覽系列'
];

// ---------- 初始化 ----------
function setupSheets() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();

  var exp = ss.getSheetByName(SHEET_EXPENSE) || ss.insertSheet(SHEET_EXPENSE);
  if (exp.getRange(1, 1).getValue() !== '展覽') {
    exp.clear();
    exp.getRange(1, 1, 1, EXPENSE_HEADERS.length).setValues([EXPENSE_HEADERS]);
    exp.setFrozenRows(1);
    exp.getRange(1, 1, 1, EXPENSE_HEADERS.length).setFontWeight('bold');
  } else if (exp.getLastColumn() < EXPENSE_HEADERS.length) {
    // 舊分頁只補上缺少的欄位標題，不動既有資料的欄位位置
    var expStart = exp.getLastColumn() + 1;
    var expMissing = EXPENSE_HEADERS.slice(exp.getLastColumn());
    exp.getRange(1, expStart, 1, expMissing.length).setValues([expMissing]);
    exp.getRange(1, expStart, 1, expMissing.length).setFontWeight('bold');
  }
  exp.setColumnWidth(13, 30);
  exp.hideColumns(13);

  var ex = ss.getSheetByName(SHEET_EXHIBITION) || ss.insertSheet(SHEET_EXHIBITION);
  if (ex.getRange(1, 1).getValue() !== '展覽名稱') {
    ex.clear();
    ex.getRange(1, 1, 1, EXHIBITION_HEADERS.length).setValues([EXHIBITION_HEADERS]);
    ex.setFrozenRows(1);
    ex.getRange(1, 1, 1, EXHIBITION_HEADERS.length).setFontWeight('bold');
  } else if (ex.getLastColumn() < EXHIBITION_HEADERS.length) {
    var exStart = ex.getLastColumn() + 1;
    var exMissing = EXHIBITION_HEADERS.slice(ex.getLastColumn());
    ex.getRange(1, exStart, 1, exMissing.length).setValues([exMissing]);
    ex.getRange(1, exStart, 1, exMissing.length).setFontWeight('bold');
  }
  ex.setColumnWidth(6, 30);
  ex.hideColumns(6);
}

// ---------- 入口 ----------
function doGet(e) {
  var action = (e.parameter.action || 'list');
  if (action === 'rate') {
    return jsonOut(getBotRate(e.parameter.date, e.parameter.currency));
  }
  return jsonOut(getAllData());
}

function doPost(e) {
  setupSheets();
  var body;
  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return jsonOut({ error: '請求格式錯誤' });
  }
  var action = body.action;
  var p = body.payload || {};
  var result;
  switch (action) {
    case 'addExpense':       result = addExpense(p); break;
    case 'updateExpense':    result = updateExpense(p); break;
    case 'deleteExpense':    result = deleteExpense(p.id); break;
    case 'addExhibition':    result = addExhibition(p); break;
    case 'updateExhibition': result = updateExhibition(p); break;
    case 'deleteExhibition': result = deleteExhibition(p.name); break;
    default: result = { error: '未知的操作：' + action };
  }
  // 每次寫入後直接回傳最新的完整資料，前端不用再多打一次
  var fresh = getAllData();
  fresh.result = result;
  return jsonOut(fresh);
}

function jsonOut(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function getSheet(name) {
  setupSheets();
  return SpreadsheetApp.getActiveSpreadsheet().getSheetByName(name);
}

// ---------- 讀取 ----------
function getAllData() {
  var exSheet = getSheet(SHEET_EXHIBITION);
  var expSheet = getSheet(SHEET_EXPENSE);

  var exValues = exSheet.getLastRow() > 1
    ? exSheet.getRange(2, 1, exSheet.getLastRow() - 1, EXHIBITION_HEADERS.length).getValues() : [];
  var expValues = expSheet.getLastRow() > 1
    ? expSheet.getRange(2, 1, expSheet.getLastRow() - 1, EXPENSE_HEADERS.length).getValues() : [];

  var exhibitions = exValues
    .filter(function (r) { return r[0] !== ''; })
    .map(function (r) {
      return {
        name: r[0], budget: r[1], cost: r[2] || 0, diff: r[3] || 0, note: r[4], id: r[5],
        country: r[6] || '', year: r[7] || '', series: r[8] || ''
      };
    });

  var expenses = expValues
    .filter(function (r) { return r[3] !== '' || r[0] !== ''; })
    .map(function (r) {
      return {
        id: r[12], exhibitionName: r[0], date: fmtDate(r[1]), category: r[2], item: r[3],
        vendor: r[4], currency: r[5], amount: r[6], rate: r[7], twd: r[8],
        payment: r[9], invoice: r[10], note: r[11],
        expenseType: r[13] || '', applicant: r[14] || ''
      };
    });

  return { exhibitions: exhibitions, expenses: expenses };
}

function fmtDate(v) {
  if (Object.prototype.toString.call(v) === '[object Date]') {
    return Utilities.formatDate(v, Session.getScriptTimeZone(), 'yyyy-MM-dd');
  }
  return v;
}

function findRowById(sheet, idColIndex, id) {
  var last = sheet.getLastRow();
  if (last < 2) return -1;
  var values = sheet.getRange(2, idColIndex, last - 1, 1).getValues();
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][0]) === String(id)) return i + 2;
  }
  return -1;
}

function makeId(prefix) {
  return prefix + new Date().getTime() + Math.floor(Math.random() * 10000);
}

// ---------- 費用明細 CRUD ----------
function addExpense(p) {
  var sheet = getSheet(SHEET_EXPENSE);
  var row = sheet.getLastRow() + 1;
  var id = makeId('x');
  var expenseType = getCategoryType(p.category);
  sheet.getRange(row, 1, 1, 8).setValues([[
    p.exhibitionName, p.date, p.category, p.item, p.vendor, p.currency, p.amount, p.rate
  ]]);
  sheet.getRange(row, 9).setFormula('=IF(OR(G' + row + '="",H' + row + '="")," ",G' + row + '*H' + row + ')');
  sheet.getRange(row, 10, 1, 3).setValues([[p.payment, p.invoice, p.note]]);
  sheet.getRange(row, 13).setValue(id);
  sheet.getRange(row, 14, 1, 2).setValues([[expenseType, expenseType === '個人' ? (p.applicant || '') : '']]);
  return { id: id };
}

function updateExpense(p) {
  var sheet = getSheet(SHEET_EXPENSE);
  var row = findRowById(sheet, 13, p.id);
  if (row < 0) return { error: '找不到這筆費用' };
  var expenseType = getCategoryType(p.category);
  sheet.getRange(row, 1, 1, 8).setValues([[
    p.exhibitionName, p.date, p.category, p.item, p.vendor, p.currency, p.amount, p.rate
  ]]);
  sheet.getRange(row, 9).setFormula('=IF(OR(G' + row + '="",H' + row + '="")," ",G' + row + '*H' + row + ')');
  sheet.getRange(row, 10, 1, 3).setValues([[p.payment, p.invoice, p.note]]);
  sheet.getRange(row, 14, 1, 2).setValues([[expenseType, expenseType === '個人' ? (p.applicant || '') : '']]);
  return { id: p.id };
}

function deleteExpense(id) {
  var sheet = getSheet(SHEET_EXPENSE);
  var row = findRowById(sheet, 13, id);
  if (row < 0) return { error: '找不到這筆費用' };
  sheet.deleteRow(row);
  return { deleted: id };
}

// ---------- 展覽總覽 CRUD ----------
function addExhibition(p) {
  var sheet = getSheet(SHEET_EXHIBITION);
  var row = sheet.getLastRow() + 1;
  var id = makeId('e');
  sheet.getRange(row, 1, 1, 2).setValues([[p.name, p.budget]]);
  sheet.getRange(row, 3).setFormula(
    '=IF(A' + row + '="","",SUMIF(' + SHEET_EXPENSE + '!$A:$A,A' + row + ',' + SHEET_EXPENSE + '!$I:$I))'
  );
  sheet.getRange(row, 4).setFormula(
    '=IF(OR(B' + row + '="",C' + row + '="")," ",B' + row + '-C' + row + ')'
  );
  sheet.getRange(row, 5).setValue(p.note || '');
  sheet.getRange(row, 6).setValue(id);
  sheet.getRange(row, 7, 1, 3).setValues([[p.country || '', p.year || '', p.series || '']]);
  return { id: id };
}

function updateExhibition(p) {
  var sheet = getSheet(SHEET_EXHIBITION);
  var row = findRowById(sheet, 6, p.id);
  if (row < 0) return { error: '找不到這個展覽' };
  var oldName = sheet.getRange(row, 1).getValue();
  sheet.getRange(row, 1, 1, 2).setValues([[p.name, p.budget]]);
  sheet.getRange(row, 5).setValue(p.note || '');
  sheet.getRange(row, 7, 1, 3).setValues([[p.country || '', p.year || '', p.series || '']]);
  // 展覽改名的話，一併更新費用明細裡對應的展覽名稱，避免加總斷掉
  if (oldName !== p.name) {
    var expSheet = getSheet(SHEET_EXPENSE);
    var last = expSheet.getLastRow();
    if (last > 1) {
      var names = expSheet.getRange(2, 1, last - 1, 1).getValues();
      for (var i = 0; i < names.length; i++) {
        if (names[i][0] === oldName) {
          expSheet.getRange(i + 2, 1).setValue(p.name);
        }
      }
    }
  }
  return { id: p.id };
}

function deleteExhibition(name) {
  var sheet = getSheet(SHEET_EXHIBITION);
  // 檢查是否還有費用明細掛在這個展覽底下
  var expSheet = getSheet(SHEET_EXPENSE);
  var last = expSheet.getLastRow();
  if (last > 1) {
    var names = expSheet.getRange(2, 1, last - 1, 1).getValues();
    for (var i = 0; i < names.length; i++) {
      if (names[i][0] === name) {
        return { error: '這個展覽底下還有費用明細，請先刪除或改指派這些費用' };
      }
    }
  }
  var last2 = sheet.getLastRow();
  if (last2 > 1) {
    var allNames = sheet.getRange(2, 1, last2 - 1, 1).getValues();
    for (var j = 0; j < allNames.length; j++) {
      if (allNames[j][0] === name) {
        sheet.deleteRow(j + 2);
        return { deleted: name };
      }
    }
  }
  return { error: '找不到這個展覽' };
}

// ---------- 台灣銀行歷史匯率 ----------
// 資料來源：rate.bot.com.tw 的每日牌告匯率 CSV（依日期查詢）
// 如果指定日期查無資料（例如假日銀行未營業），會自動往前找最近的營業日
function getBotRate(dateStr, currency) {
  currency = (currency || 'USD').toUpperCase().trim();
  if (currency === 'TWD') {
    return { date: dateStr, currency: 'TWD', spotBuy: 1, spotSell: 1, cashBuy: 1, cashSell: 1 };
  }
  var d = dateStr ? new Date(dateStr + 'T00:00:00') : new Date();

  for (var tries = 0; tries < 7; tries++) {
    var tryDateStr = Utilities.formatDate(d, Session.getScriptTimeZone(), 'yyyy-MM-dd');
    var url = 'https://rate.bot.com.tw/xrt/flcsv/0/' + tryDateStr;
    try {
      var res = UrlFetchApp.fetch(url, { muteHttpExceptions: true });
      if (res.getResponseCode() === 200) {
        var text = res.getContentText('UTF-8').replace(/^﻿/, '');
        var lines = text.split('\n');
        for (var i = 1; i < lines.length; i++) {
          var cols = lines[i].split(',');
          if (cols.length < 14) continue;
          if (cols[0].trim().toUpperCase() === currency) {
            var cashBuy = parseFloat(cols[2]);
            var spotBuy = parseFloat(cols[3]);
            var cashSell = parseFloat(cols[12]);
            var spotSell = parseFloat(cols[13]);
            if (spotBuy || spotSell) {
              return {
                date: tryDateStr,
                requestedDate: dateStr,
                currency: currency,
                cashBuy: cashBuy || null,
                spotBuy: spotBuy || null,
                cashSell: cashSell || null,
                spotSell: spotSell || null,
                usedFallback: tryDateStr !== dateStr
              };
            }
          }
        }
      }
    } catch (err) {
      // 忽略，繼續往前一天找
    }
    d.setDate(d.getDate() - 1);
  }
  return { error: '查無「' + currency + '」自 ' + dateStr + ' 起前7天內的匯率資料，該幣別可能不支援或非本行牌告幣別' };
}
