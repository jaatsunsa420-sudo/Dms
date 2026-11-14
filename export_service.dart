import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ExportService {
  static Future<File> generateTripsExcel(List<Map<String, dynamic>> trips) async {
    final excel = Excel.createExcel();
    final sheet = excel['Trips Report'];
    excel.delete('Sheet1');
    sheet.appendRow(['Date','Vehicle','From','To','Via','Goods','Qty','Unit','Bilty','KM','Diesel','Notes'].map((e)=>TextCellValue(e)).toList());
    for (final t in trips) {
      sheet.appendRow([
        TextCellValue('${t['trip_date']??''}'), TextCellValue('${t['vehicle_number']??''}'),
        TextCellValue('${t['loading_station']??''}'), TextCellValue('${t['unloading_station']??''}'),
        TextCellValue('${t['via_stations']??''}'), TextCellValue('${t['goods_name']??''}'),
        DoubleCellValue((t['quantity'] as num?)?.toDouble() ?? 0), TextCellValue('${t['unit']??''}'),
        TextCellValue('${t['bilty_number']??''}'), TextCellValue('${t['kilometres']??''}'),
        TextCellValue('${t['diesel_litres']??''}'), TextCellValue('${t['notes']??''}'),
      ]);
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Driver_Trips_${DateTime.now().millisecondsSinceEpoch}.xlsx');
    final b = excel.save(); if (b != null) await file.writeAsBytes(b, flush: true);
    return file;
  }

  static Future<File> generateTripsPdf(List<Map<String, dynamic>> trips, String driverName) async {
    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      build: (_) => [
        pw.Text('Driver Trip Report - $driverName', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Date','Vehicle','From','To','Goods','Qty','Bilty','KM','Diesel'],
          data: trips.map((t) => ['${t['trip_date']}','${t['vehicle_number']}','${t['loading_station']}','${t['unloading_station']}','${t['goods_name']}','${t['quantity']} ${t['unit']}','${t['bilty_number']??'-'}','${t['kilometres']??'-'}','${t['diesel_litres']??'-'}']).toList(),
        ),
      ],
    ));
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Driver_Trips_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await pdf.save(), flush: true);
    return file;
  }

  static Future<File> generateTripsDocx(List<Map<String, dynamic>> trips, String driverName) async {
    String esc(dynamic v) => (v ?? '').toString().replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    final rows = StringBuffer('<w:tr>${['Date','Vehicle','From -> To','Goods','Bilty'].map((h)=>'<w:tc><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>${esc(h)}</w:t></w:r></w:p></w:tc>').join()}</w:tr>');
    for (final t in trips) {
      rows.write('<w:tr>${[t['trip_date'],t['vehicle_number'],'${t['loading_station']} -> ${t['unloading_station']}','${t['goods_name']} (${t['quantity']} ${t['unit']})',t['bilty_number']??'-'].map((c)=>'<w:tc><w:p><w:r><w:t>${esc(c)}</w:t></w:r></w:p></w:tc>').join()}</w:tr>');
    }
    final docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Trip Report - ${esc(driverName)}</w:t></w:r></w:p><w:tbl>$rows</w:tbl></w:body></w:document>';
    const ctXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
    const relsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
    final arc = Archive()..addFile(ArchiveFile('[Content_Types].xml', ctXml.length, utf8.encode(ctXml)))..addFile(ArchiveFile('_rels/.rels', relsXml.length, utf8.encode(relsXml)))..addFile(ArchiveFile('word/document.xml', docXml.length, utf8.encode(docXml)));
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Driver_Trips_${DateTime.now().millisecondsSinceEpoch}.docx');
    await file.writeAsBytes(ZipEncoder().encode(arc)!, flush: true);
    return file;
  }

  static Future<File> generateTripsCsv(List<Map<String, dynamic>> trips) async {
    final sb = StringBuffer('Date,Vehicle,From,To,Goods,Qty,Unit,Bilty,KM,Diesel
');
    for (final t in trips) {
      sb.writeln([t['trip_date'],t['vehicle_number'],t['loading_station'],t['unloading_station'],t['goods_name'],t['quantity'],t['unit'],t['bilty_number'],t['kilometres'],t['diesel_litres']].map((e)=>'"${(e??'').toString().replaceAll('"','""')}"').join(','));
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Driver_Trips_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString('﻿${sb.toString()}', flush: true);
    return file;
  }

  static Future<void> createAutoRetentionBackup(List<Map<String, dynamic>> trips) async {
    final dir = await getApplicationDocumentsDirectory();
    final bDir = Directory('${dir.path}/auto_retention_backups');
    if (!await bDir.exists()) await bDir.create(recursive: true);
    await File('${bDir.path}/archived_${DateTime.now().toIso8601String().substring(0,10)}.json').writeAsString(jsonEncode(trips), flush: true);
  }

  static Future<void> shareFile(File file) async => await Share.shareXFiles([XFile(file.path)], text: 'Driver Trip Report');
}
