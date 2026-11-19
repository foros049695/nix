-- DADOS SINTETICOS. Chaves zeradas NAO sao identidades validas para uso real.
INSERT INTO identities VALUES('local-test','NIX-SYNTHETIC',zeroblob(32),zeroblob(32),'vault-synthetic',1730000000000);
INSERT INTO conversations VALUES('saved-test','saved','local-test','Mensagens Salvas',0,1730000000000,1730000000000);
INSERT INTO messages(id,conversation_id,author_key,device_id,body,created_at,delivery_state) VALUES('msg-test','saved-test','synthetic-author','synthetic-device','Nota sintetica para pesquisa',1730000000000,'received');
INSERT INTO folders VALUES('folder-test','Teste',0,NULL,'folder');
INSERT INTO folder_conversations VALUES('folder-test','saved-test',0);
INSERT INTO media_items(id,kind,title,updated_at) VALUES('book-test','book','Livro sintetico',1730000000000);
INSERT INTO library_entries(identity_id,media_id,saved_at) VALUES('local-test','book-test',1730000000000);
