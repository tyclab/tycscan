import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/file-docs.py"


class FilingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / "archive"
        self.archive.mkdir()
        self.pdf = self.root / "scan.pdf"
        self.pdf.write_text("Invoice number 12345678")
        self.spec = self.root / "spec.tsv"
        self.journal = self.root / "journal.csv"
        tools = self.root / "tools"
        tools.mkdir()
        for name, body in {
            "qpdf": "import shutil,sys\nshutil.copyfile(sys.argv[3],sys.argv[-1])\n",
            "pdftotext": "import pathlib,sys\ns=pathlib.Path(sys.argv[-2]).read_text()\n"
                         "if s.startswith('FAIL'): sys.exit(1)\nprint(s)\n",
        }.items():
            path = tools / name
            path.write_text("#!/usr/bin/env python3\n" + body)
            path.chmod(0o755)
        self.env = {**os.environ, "PATH": str(tools) + os.pathsep + os.environ["PATH"]}

    def file(self, rows):
        self.spec.write_text(rows)
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.pdf), str(self.spec), str(self.archive),
             str(self.journal), "batch-test"], cwd=self.root, env=self.env,
            text=True, capture_output=True, timeout=10,
        )

    def assert_refused(self, rows):
        result = self.file(rows)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.journal.exists())
        return result

    def test_relative_destination_and_valid_blank_extraction_can_be_filed(self):
        for number, text in enumerate(("Invoice number 12345678", "")):
            with self.subTest(text=text):
                self.pdf.write_text(text)
                target = f"folder-{number}/document.pdf"
                result = self.file(f"1\t{target}\n")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual((self.archive / target).read_text(), text)
                self.assertIn("scan,", self.journal.read_text())

    def test_parent_and_absolute_destinations_are_rejected_before_any_filing(self):
        for target in ("../outside.pdf", str(self.root / "outside.pdf")):
            with self.subTest(target=target):
                self.assert_refused(f"1\tvalid.pdf\n2\t{target}\n")
                self.assertFalse((self.archive / "valid.pdf").exists())
                self.assertFalse((self.root / "outside.pdf").exists())

    def test_symlink_destination_cannot_escape_archive(self):
        outside = self.root / "outside"
        outside.mkdir()
        (self.archive / "link").symlink_to(outside, target_is_directory=True)
        self.assert_refused("1\tlink/document.pdf\n")
        self.assertEqual(list(outside.iterdir()), [])

    def test_replacement_source_cannot_escape_archive(self):
        outside = self.root / "outside.pdf"
        outside.write_text("original")
        (self.archive / "link.pdf").symlink_to(outside)
        for source in ("../outside.pdf", "link.pdf"):
            with self.subTest(source=source):
                self.assert_refused(f"1\tREPLACE {source} => new.pdf\n")
                self.assertEqual(outside.read_text(), "original")

    def test_recycle_symlink_cannot_escape_archive(self):
        old = self.archive / "old.pdf"
        old.write_text("original")
        outside = self.root / "outside"
        outside.mkdir()
        (self.archive / "_Papierkorb").symlink_to(outside, target_is_directory=True)
        self.assert_refused("1\tREPLACE old.pdf => new.pdf\n")
        self.assertEqual(old.read_text(), "original")
        self.assertEqual(list(outside.iterdir()), [])

    def test_valid_replacement_retains_old_file_in_recycle_directory(self):
        (self.archive / "old.pdf").write_text("original")
        result = self.file("1\tREPLACE old.pdf => new.pdf\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.archive / "old.pdf").exists())
        self.assertEqual((self.archive / "_Papierkorb/ersetzt/old.pdf").read_text(), "original")
        self.assertEqual((self.archive / "new.pdf").read_text(), self.pdf.read_text())
        self.assertIn("scan-replace,", self.journal.read_text())

    def test_failed_document_extraction_never_files_or_journals(self):
        self.pdf.write_text("FAIL encrypted or corrupt input")
        self.assert_refused("1\tdocument.pdf\n")
        self.assertFalse((self.archive / "document.pdf").exists())

    def test_failed_replacement_extraction_preserves_original_without_journal(self):
        old = self.archive / "old.pdf"
        old.write_text("original")
        self.pdf.write_text("FAIL encrypted or corrupt replacement")
        for target in ("old.pdf", "new.pdf"):
            with self.subTest(target=target):
                self.assert_refused(f"1\tREPLACE old.pdf => {target}\n")
                self.assertEqual(old.read_text(), "original")
                self.assertFalse((self.archive / "new.pdf").exists())
                self.assertFalse((self.archive / "_Papierkorb").exists())

    def test_failed_archive_extraction_is_not_ignored(self):
        (self.archive / "unreadable.pdf").write_text("FAIL corrupt archive PDF")
        self.assert_refused("1\tdocument.pdf\n")
        self.assertFalse((self.archive / "document.pdf").exists())
