-- DADOS SINTETICOS. Tokens e payloads de teste, SEM seguranca criptografica.
INSERT INTO nix.mailboxes(id,expires_at) VALUES(repeat('a',64),clock_timestamp()+interval '30 days');
INSERT INTO nix.capabilities(mailbox_id,scope,token_hash,expires_at) VALUES(repeat('a',64),'write',public.digest('SYNTHETIC-WRITE','sha256'),clock_timestamp()+interval '30 days');
SELECT * FROM nix.put_envelope(repeat('a',64),'00000000-0000-4000-8000-000000000001',decode('01020304','hex'),3600);
