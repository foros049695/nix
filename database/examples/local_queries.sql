-- Bind parameters no adapter; timestamps locais sao Unix milissegundos UTC.
SELECT id,body,created_at FROM messages WHERE conversation_id=:conversation_id AND deleted_at IS NULL AND (expires_at IS NULL OR expires_at>:now_ms) AND (created_at,id)<(:before_time,:before_id) ORDER BY created_at DESC,id DESC LIMIT 50;
SELECT m.id,m.body FROM message_search s JOIN messages m ON m.id=s.message_id WHERE message_search MATCH :fts_query AND m.conversation_id=:conversation_id LIMIT 50;
SELECT id,ciphertext FROM outbox WHERE transport_state='queued' AND next_attempt_at<=:now_ms AND expires_at>:now_ms ORDER BY next_attempt_at LIMIT 20;
-- Uma transacao do caso de uso tambem remove eventos, FTS e referencia a anexos por cascata.
DELETE FROM messages WHERE expires_at IS NOT NULL AND expires_at<=:now_ms;
-- GC de objetos requer conferir referencias de perfil/acervo antes de apagar arquivo.
SELECT o.id FROM objects o WHERE NOT EXISTS(SELECT 1 FROM attachments a WHERE a.object_id=o.id);
