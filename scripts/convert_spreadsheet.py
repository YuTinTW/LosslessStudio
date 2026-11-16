#!/usr/bin/env python3
import sys
import os
import argparse
import csv
import zipfile
import xml.etree.ElementTree as ET

def parse_xlsx_builtin(path):
    ns = {'main': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    sheets = {}
    with zipfile.ZipFile(path, 'r') as z:
        shared_strings = []
        if 'xl/sharedStrings.xml' in z.namelist():
            try:
                tree = ET.fromstring(z.read('xl/sharedStrings.xml'))
                for si in tree.findall('main:si', ns):
                    t = si.find('main:t', ns)
                    shared_strings.append(t.text if t is not None and t.text else '')
            except Exception:
                pass

        for name in sorted(z.namelist()):
            if name.startswith('xl/worksheets/sheet') and name.endswith('.xml'):
                try:
                    tree = ET.fromstring(z.read(name))
                    sheet_data = tree.find('main:sheetData', ns)
                    rows = []
                    if sheet_data is not None:
                        for row in sheet_data.findall('main:row', ns):
                            row_vals = []
                            for c in row.findall('main:c', ns):
                                t_attr = c.attrib.get('t', '')
                                val = ''
                                if t_attr == 'inlineStr':
                                    is_tag = c.find('main:is', ns)
                                    if is_tag is not None:
                                        t_tag = is_tag.find('main:t', ns)
                                        if t_tag is not None and t_tag.text:
                                            val = t_tag.text
                                else:
                                    v_tag = c.find('main:v', ns)
                                    if v_tag is not None and v_tag.text:
                                        val = v_tag.text
                                        if t_attr == 's' and val.isdigit():
                                            idx = int(val)
                                            if idx < len(shared_strings):
                                                val = shared_strings[idx]
                                row_vals.append(val)
                            rows.append(row_vals)
                    base_name = os.path.splitext(os.path.basename(name))[0]
                    sheets[base_name] = rows
                except Exception:
                    continue
    return sheets

def read_sheets(in_path, ext):
    # 嘗試 pandas
    try:
        import pandas as pd
        sheets = {}
        if ext in [".xlsx", ".xls"]:
            xls = pd.ExcelFile(in_path)
            for sname in xls.sheet_names:
                df = pd.read_excel(xls, sheet_name=sname).fillna("")
                rows = [list(df.columns)] + df.values.tolist()
                sheets[sname] = [[str(x) for x in r] for r in rows]
            return sheets
        elif ext == ".csv":
            df = pd.read_csv(in_path).fillna("")
            rows = [list(df.columns)] + df.values.tolist()
            return {"Sheet1": [[str(x) for x in r] for r in rows]}
        elif ext == ".tsv":
            df = pd.read_csv(in_path, sep="\t").fillna("")
            rows = [list(df.columns)] + df.values.tolist()
            return {"Sheet1": [[str(x) for x in r] for r in rows]}
    except Exception:
        pass

    # 內建模組 Fallback
    sheets = {}
    if ext == ".xlsx":
        sheets = parse_xlsx_builtin(in_path)
    elif ext in [".csv", ".tsv"]:
        delimiter = "\t" if ext == ".tsv" else ","
        try:
            with open(in_path, "r", encoding="utf-8-sig", errors="replace") as f:
                reader = csv.reader(f, delimiter=delimiter)
                sheets["Sheet1"] = [row for row in reader]
        except Exception as e:
            print(f"Error reading {ext}: {e}", file=sys.stderr)
            sys.exit(2)
    else:
        print(f"Error: unsupported spreadsheet extension {ext}", file=sys.stderr)
        sys.exit(2)

    return sheets

def main():
    parser = argparse.ArgumentParser(description="Convert Excel/Spreadsheets to HTML, CSV, or Text")
    parser.add_argument("--input", required=True, help="Input spreadsheet path (.xlsx, .xls, .csv, .tsv)")
    parser.add_argument("--output", required=True, help="Output file path")
    parser.add_argument("--format", required=True, choices=["html", "csv", "tsv", "txt"], help="Target format")
    args = parser.parse_args()

    in_path = os.path.abspath(args.input)
    out_path = os.path.abspath(args.output)

    if not os.path.exists(in_path):
        print(f"Error: input file not found: {in_path}", file=sys.stderr)
        sys.exit(1)

    ext = os.path.splitext(in_path)[1].lower()
    sheets_dict = read_sheets(in_path, ext)

    if not sheets_dict:
        print(f"Error: no sheets parsed from {in_path}", file=sys.stderr)
        sys.exit(2)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)

    if args.format == "csv":
        first_sheet = list(sheets_dict.values())[0]
        with open(out_path, "w", encoding="utf-8-sig", newline="") as f:
            writer = csv.writer(f)
            for r in first_sheet:
                writer.writerow(r)
    elif args.format in ["tsv", "txt"]:
        first_sheet = list(sheets_dict.values())[0]
        with open(out_path, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, delimiter="\t")
            for r in first_sheet:
                writer.writerow(r)
    elif args.format == "html":
        html_parts = [
            "<!DOCTYPE html>",
            "<html><head><meta charset='utf-8'>",
            "<style>",
            "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; margin: 30px; color: #222; }",
            "h2 { font-size: 16px; margin-top: 24px; margin-bottom: 8px; color: #d35400; border-bottom: 1px solid #eee; padding-bottom: 4px; }",
            "table { border-collapse: collapse; width: 100%; margin-bottom: 20px; font-size: 11px; }",
            "th, td { border: 1px solid #dcdde1; padding: 6px 10px; text-align: left; }",
            "th { background-color: #f5f6fa; font-weight: bold; color: #2f3640; }",
            "tr:nth-child(even) { background-color: #fafafa; }",
            "</style></head><body>"
        ]
        for sheet_name, rows in sheets_dict.items():
            html_parts.append(f"<h2>工作表：{sheet_name}</h2>")
            if not rows:
                html_parts.append("<p>（空工作表）</p>")
                continue
            html_parts.append("<table border='1'>")
            # 第一列作為表頭
            header = rows[0]
            html_parts.append("<thead><tr>" + "".join(f"<th>{cell}</th>" for cell in header) + "</tr></thead>")
            html_parts.append("<tbody>")
            for r in rows[1:]:
                html_parts.append("<tr>" + "".join(f"<td>{cell}</td>" for cell in r) + "</tr>")
            html_parts.append("</tbody></table>")
        html_parts.append("</body></html>")

        with open(out_path, "w", encoding="utf-8") as f:
            f.write("\n".join(html_parts))

    print(f"Spreadsheet converted successfully: {out_path}")

if __name__ == "__main__":
    main()
