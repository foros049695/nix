import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/core/database/repositories.dart' as barrel;
import 'package:nix_client/core/database/repositories/identity_repository.dart'
    as identity_repository;
import 'package:nix_client/core/database/repositories/contact_repository.dart'
    as contact_repository;
import 'package:nix_client/core/database/repositories/conversation_repository.dart'
    as conversation_repository;
import 'package:nix_client/core/database/repositories/message_repository.dart'
    as message_repository;
import 'package:nix_client/core/database/repositories/outbox_repository.dart'
    as outbox_repository;
import 'package:nix_client/core/database/repositories/media_repository.dart'
    as media_repository;
import 'package:nix_client/core/database/repositories/preferences_repository.dart'
    as preferences_repository;
import 'package:nix_client/core/database/repositories/key_material_repository.dart'
    as key_material_repository;
import 'package:nix_client/core/database/repositories/pre_key_repository.dart'
    as pre_key_repository;
import 'package:nix_client/core/database/repositories/session_repository.dart'
    as session_repository;
import 'package:nix_client/core/database/repositories/object_chunk_repository.dart'
    as object_chunk_repository;
import 'package:nix_client/core/database/repositories/archive_repository.dart'
    as archive_repository;

void main() {
  test('o barrel preserva a identidade dos 12 repositórios separados', () {
    expect(barrel.IdentityRepository, identity_repository.IdentityRepository);
    expect(barrel.ContactRepository, contact_repository.ContactRepository);
    expect(barrel.ConversationRepository,
        conversation_repository.ConversationRepository);
    expect(barrel.MessageRepository, message_repository.MessageRepository);
    expect(barrel.OutboxRepository, outbox_repository.OutboxRepository);
    expect(barrel.MediaRepository, media_repository.MediaRepository);
    expect(barrel.PreferencesRepository,
        preferences_repository.PreferencesRepository);
    expect(barrel.KeyMaterialRepository,
        key_material_repository.KeyMaterialRepository);
    expect(barrel.PreKeyRepository, pre_key_repository.PreKeyRepository);
    expect(barrel.SessionRepository, session_repository.SessionRepository);
    expect(barrel.ObjectChunkRepository,
        object_chunk_repository.ObjectChunkRepository);
    expect(barrel.ArchiveRepository, archive_repository.ArchiveRepository);
  });
}
