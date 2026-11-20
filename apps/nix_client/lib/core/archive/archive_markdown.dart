import 'package:markdown/markdown.dart' as md;

import 'nix_archive_service.dart';

/// Converte a marcação do editor para o campo HTML já assinado pelo Archive.
String compileArchiveMarkdown(String markdown) {
  final checklist = markdown.replaceAllMapped(
    RegExp(r'^([ \t]*[-*+] +)\[( |x|X)\](?=\s)', multiLine: true),
    (match) => '${match[1]}${match[2] == ' ' ? '☐' : '☑'}',
  );
  final html = md.markdownToHtml(
    checklist,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: true,
  );
  return NixArchiveService.sanitizeRichTextHtml(html);
}
