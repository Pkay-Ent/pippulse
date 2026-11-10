-- Raise the existing Community Chat image bucket limit from 5 MiB to 10 MiB.
-- Keep the bucket private and retain the existing MIME type allow-list.
begin;

update storage.buckets
set file_size_limit = 10485760,
    allowed_mime_types = array['image/jpeg','image/png','image/webp'],
    public = false
where id = 'community-chat-images';

commit;
