-- Run in psql on a locally restored MusicBrainz core database.
SET search_path TO musicbrainz, public;
CREATE TEMP VIEW nix_musicbrainz_works AS
WITH records AS (
    SELECT rg.gid AS album_mbid, rg.name AS album, ac.name AS artist,
           rgm.first_release_date_year AS year, r.id AS release_id
    FROM release_group rg
    JOIN release_group_primary_type typ ON typ.id = rg.type AND typ.name = 'Album'
    JOIN artist_credit ac ON ac.id = rg.artist_credit
    LEFT JOIN release_group_meta rgm ON rgm.id = rg.id
    LEFT JOIN release r ON r.release_group = rg.id
), works AS (
    SELECT DISTINCT 'album' AS kind, album_mbid AS mbid, album AS title,
                    artist, NULL::text AS album, year
    FROM records
    UNION ALL
    (SELECT DISTINCT ON (rec.gid) 'track', rec.gid, rec.name,
                       ac.name, a.album, a.year
    FROM records a
    JOIN medium m ON m.release = a.release_id
    JOIN track t ON t.medium = m.id
    JOIN recording rec ON rec.id = t.recording
    JOIN artist_credit ac ON ac.id = rec.artist_credit
    ORDER BY rec.gid, a.year NULLS LAST, a.album_mbid)
)
SELECT * FROM works;
\copy nix_musicbrainz_works TO STDOUT WITH (FORMAT csv, DELIMITER E'\t', HEADER true)
