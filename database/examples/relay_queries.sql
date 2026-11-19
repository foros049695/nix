-- Exemplos psql: definir box, cap_hash_hex e cursor com valores sinteticos.
-- Auth deve anteceder TODA operacao no servico, com hash de dominio calculado.
SELECT mailbox_id,scope FROM nix.capabilities WHERE token_hash=decode(:'cap_hash_hex','hex') AND mailbox_id=:'box' AND revoked_at IS NULL AND expires_at>clock_timestamp();
-- Primeiro lote; cursor subsequente usa comparacao (created_at,id)>($time,$id).
SELECT id,delivery_id,ciphertext,expires_at FROM nix.envelopes WHERE mailbox_id=:'box' AND state='pending' AND expires_at>clock_timestamp() ORDER BY created_at,id LIMIT 100;
-- Adapter limita tambem bytes agregados por pagina, antes de construir resposta.
SELECT nix.sweep_expired(500);
SELECT m.id,m.used_bytes,coalesce(sum(e.byte_size) FILTER(WHERE e.state='pending'),0) AS computed FROM nix.mailboxes m LEFT JOIN nix.envelopes e ON e.mailbox_id=m.id GROUP BY m.id HAVING m.used_bytes<>coalesce(sum(e.byte_size) FILTER(WHERE e.state='pending'),0);
