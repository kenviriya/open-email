# Open Email HTTP contract

The Go API owns `/api/*`. Next.js forwards `/api/*` to `API_INTERNAL_URL` (default `http://app:8080`), so the browser stays on one origin.
JSON fields are snake_case. Errors are `{"error":{"code":"string","message":"human readable"}}`.
Auth uses an HttpOnly `oe_session` cookie (SameSite=Lax, Secure when PUBLIC_URL is https). Mutating session calls must send `Origin` equal to PUBLIC_URL.

## Setup (only while setup is not complete)
- `GET /api/setup/status` -> `{"step":"admin|resend|domain|storage|finish|done","needs_reentry":bool,"public_url":"https://..."}`
- `POST /api/setup/admin` `{email,password,name}` -> 201 + session cookie. Password min 12 chars. Locked once an admin exists.
- `POST /api/setup/resend` `{api_key}` -> `{"domains":[Domain]}`; 400 `resend_key_invalid`, 403 `resend_key_sending_only`.
- `POST /api/setup/domain/check` `{domain}` -> `DomainCheck`.
- `POST /api/setup/domain` `{domain, replace_existing_mx:bool, mailbox_local_part}` -> `DomainCheck`. Creates the domain in Resend if needed, the admin mailbox, and the catch-all mailbox.
- `POST /api/setup/storage` `{account_id,access_key_id,secret_access_key,bucket,jurisdiction:"default|eu|fedramp"}` -> `StorageCheck`. Saves only when `ok`.
- `POST /api/setup/finish` -> `{"webhook":"ok","test_message_id":"uuid","fallback_polling":bool}`.

`Domain` = `{id,name,status,region,receiving_enabled}`
`DomainCheck` = `{domain,resend_domain_id,status,conflict:bool,provider:"Google Workspace|Microsoft 365|Zoho|Proton|Fastmail|another provider|",current_mx:[string],required_records:[{type,name,value,priority,status}],suggested_subdomain:"mail.example.com"}`
`StorageCheck` = `{ok:bool,checks:[{name:"endpoint|write|read|metadata|delete|least_privilege",ok:bool,message}],error_code:""}`

Token permission rule: the token must be able to put, get, head and delete a test object in the chosen bucket. It must **not** be able to list account buckets. A ListBuckets success means an Admin token, so it is rejected with `r2_token_too_broad`. An Object Read & Write token scoped to all buckets cannot be told apart from one scoped to a single bucket through the S3 API alone; the UI states this.

## Auth and session
- `POST /api/auth/login` `{email,password}` -> `{user}`. Rate limited per IP and email.
- `POST /api/auth/logout` -> 204.
- `GET /api/me` -> `{user:{id,email,name,role},mailboxes:[Mailbox]}`.

`Mailbox` = `{id,address,display_name,signature_html,unread_count}`

## Mail
- `GET /api/mailboxes/:mailbox/threads?folder=inbox|sent|drafts|archive|trash|spam|starred&q=&cursor=` -> `{threads:[Thread],next_cursor}`
- `GET /api/threads/:id` -> `{thread:Thread,messages:[Message]}`
- `PATCH /api/threads/:id` `{is_read?,is_starred?,folder?}` -> `{thread}`
- `POST /api/attachments?mailbox_id=` multipart `file` -> `Attachment` (rejects files that cannot fit in a message)
- `DELETE /api/attachments/:id` -> 204 (unsent uploads only)
- `GET /api/attachments/:id/download` -> 302 to a short-lived presigned R2 URL
- `POST /api/messages/drafts` and `PATCH /api/messages/drafts/:id` `Draft` -> `{message}`
- `POST /api/messages/send` `Draft` -> 202 `{message}`; 413 `message_too_large`
- `GET /api/events` -> SSE events `message.created`, `message.updated`, `thread.updated` with `{mailbox_id,thread_id,message_id}`

`Draft` = `{id?,mailbox_id,to:[string],cc:[string],bcc:[string],subject,html,text?,attachment_ids:[uuid],reply_to_message_id?,forward_message_id?,forward_attachment_ids?:[uuid]}`
`Thread` = `{id,mailbox_id,subject,snippet,participants:[string],last_message_at,message_count,unread_count,is_starred,folder,has_attachments}`
`Message` = `{id,thread_id,mailbox_id,direction:"inbound|outbound",status,from,to,cc,bcc,subject,html,text,sent_at,received_at,is_read,attachments:[Attachment],auth_result,error_message}`
`Attachment` = `{id,filename,content_type,size,content_id,inline,download_url}`

## Admin
- `GET|POST /api/admin/users`, `PATCH|DELETE /api/admin/users/:id`
- `GET|POST /api/admin/mailboxes`, `PATCH|DELETE /api/admin/mailboxes/:id`, `PUT /api/admin/mailboxes/:id/members` `{user_ids}`
- `GET /api/admin/integrations` -> masked Resend, domain, R2 and webhook state (never secrets)
- `PUT /api/admin/integrations/resend` `{api_key}`, `PUT /api/admin/integrations/storage` `StorageInput` (same checks as setup)

## Limits
Message size: sum of `ceil(bytes/3)*4` for every attachment, plus HTML bytes, text bytes and 65536, must be at most 40,000,000.
