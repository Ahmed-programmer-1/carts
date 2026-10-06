-- ============================================================
-- مكتبتي — ملف SQL واحد شامل لكل الخطوات (1 → 11)
-- شغّله مرة واحدة كامل في: Supabase Dashboard > SQL Editor > New query > Run
-- بعد التشغيل، لازم تدوّر نفسك أدمن يدويًا — دوّر على "admins" تحت
-- ============================================================



-- ============================================================
-- 🧨 ابدأ من جديد — مفعّل في النسخة دي
-- ============================================================
-- القسم ده بيمسح كل جدول ودالة بتاعت المشروع ده بالكامل، عشان
-- باقي الملف يشتغل على قاعدة فاضية من غير أخطاء "already exists".
-- ⚠️ خطر حقيقي: هيمسح كل البيانات نهائيًا ومفيش استرجاع بعدها.
-- ⚠️ مش بيمسح حسابات auth.users نفسها — ده يدوي من
-- Authentication > Users في لوحة Supabase لو احتجته.
-- ============================================================

drop table if exists public.audit_log cascade;
drop table if exists public.admin_chat_messages cascade;
drop table if exists public.admin_user_notes cascade;
drop table if exists public.purchase_inquiries cascade;
drop table if exists public.course_views cascade;
drop table if exists public.contact_messages cascade;
drop table if exists public.card_reports cascade;
drop table if exists public.card_comments cascade;
drop table if exists public.card_share_views cascade;
drop table if exists public.notifications cascade;
drop table if exists public.site_settings cascade;
drop table if exists public.files cascade;
drop table if exists public.cards cascade;
drop table if exists public.profile_private cascade;
drop table if exists public.admins cascade;
drop table if exists public.profiles cascade;
drop table if exists public.login_events cascade;

drop function if exists public.admin_approve_card cascade;
drop function if exists public.admin_dismiss_report cascade;
drop function if exists public.admin_get_chat_threads cascade;
drop function if exists public.admin_get_day_logins cascade;
drop function if exists public.admin_get_day_summary cascade;
drop function if exists public.admin_get_login_trend cascade;
drop function if exists public.admin_get_online_now cascade;
drop function if exists public.admin_get_pending_cards cascade;
drop function if exists public.admin_get_reported_cards cascade;
drop function if exists public.admin_get_top_cards cascade;
drop function if exists public.admin_get_top_courses cascade;
drop function if exists public.admin_get_trashed_cards cascade;
drop function if exists public.admin_restore_card cascade;
drop function if exists public.enforce_card_approval cascade;
drop function if exists public.enforce_card_limit cascade;
drop function if exists public.file_storage_accessible cascade;
drop function if exists public.get_shared_card cascade;
drop function if exists public.handle_new_user cascade;
drop function if exists public.handle_new_user_private cascade;
drop function if exists public.is_admin cascade;
drop function if exists public.protect_disabled_field cascade;
drop function if exists public.set_audit_admin cascade;
drop function if exists public.set_chat_sender cascade;
drop function if exists public.set_comment_user cascade;
drop function if exists public.set_contact_user cascade;
drop function if exists public.set_purchase_user cascade;
drop function if exists public.set_report_reporter cascade;
drop function if exists public.set_share_view_owner cascade;
drop function if exists public.touch_last_seen cascade;
drop function if exists public.track_notification_dismiss cascade;
drop function if exists public.track_notification_view cascade;

drop policy if exists "storage_select" on storage.objects;
drop policy if exists "storage_insert_own" on storage.objects;
drop policy if exists "storage_delete_own" on storage.objects;
drop policy if exists "storage_delete_admin" on storage.objects;

-- ⚠️ ملفات الـStorage (bucket "study-files") ما ينفعش تتمسح بأمر SQL
-- مباشر — Supabase بيمنع ده عمدًا لحماية البيانات. لو عايز تمسح
-- الملفات القديمة كمان، روح Storage من القائمة الجانبية في لوحة
-- Supabase، افتح bucket اسمه "study-files"، وامسح محتواه يدويًا من
-- هناك. الجزء اللي تحت هيعيد إنشاء الـbucket لو مش موجود أصلاً
-- (on conflict do nothing) فمش هيدّيك خطأ حتى لو سبته زي ما هو.

-- ############################################################
-- من ملف: schema.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الأساس: نظام الحسابات (Auth Foundation)
-- شغّل هذا الملف كامل مرة واحدة في: Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- جدول البروفايلات العامة: الاسم اللي يظهر للمستخدمين الآخرين
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null,
  created_at timestamptz not null default now()
);

-- اسم المستخدم فريد بغض النظر عن حالة الأحرف (Ahmed = ahmed)
create unique index profiles_username_lower_idx on public.profiles (lower(username));

alter table public.profiles enable row level security;

-- أي حد (حتى لو مش مسجل دخول) يقدر يشوف اسم المستخدم والاسم الظاهر —
-- ده اللي بيخلي صفحة بروفايل أي مستخدم قابلة للعرض لاحقًا، ويسمح بالتحقق
-- من تكرار اسم المستخدم وقت التسجيل
create policy "profiles_public_read"
  on public.profiles for select
  using (true);

-- المستخدم يعدّل بروفايله هو بس (هنستخدمها لاحقًا لو أضفنا تعديل الاسم)
create policy "profiles_self_update"
  on public.profiles for update
  using (auth.uid() = id);

-- ملحوظة: مفيش policy لل insert قصدًا — الإدخال الوحيد المسموح بيحصل
-- تلقائيًا عن طريق الـ trigger تحت (اللي بيشتغل بصلاحيات أعلى من صلاحيات
-- المستخدم العادي)، مش من الكلاينت مباشرة.

-- الدالة دي بتتنفذ تلقائيًا كل ما يتسجل مستخدم جديد في auth.users،
-- وبتاخد username و display_name اللي بعتناهم وقت signUp (عبر options.data)
-- وتحطهم في جدول profiles
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    new.raw_user_meta_data ->> 'display_name'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ############################################################
-- من ملف: schema_02_cards.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 2: نظام الـCards ورفع الملفات
-- شغّل هذا الملف بعد schema.sql (الخاص بالحسابات) — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- جدول البطاقات ----------------
create table public.cards (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  -- private: مايشوفهاش غير صاحبها
  -- unlisted: مايظهرش في أي تصفح عام، بس يتفتح برابط المشاركة
  -- public: يظهر لأي حد (هنستخدمها لاحقًا لو عملنا مكتبة عامة لكروت المستخدمين)
  visibility text not null default 'private' check (visibility in ('private','unlisted','public')),
  allow_download boolean not null default true,
  share_token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.cards enable row level security;

create policy "cards_select_own_or_public"
  on public.cards for select
  using (owner_id = auth.uid() or visibility = 'public');

create policy "cards_insert_own"
  on public.cards for insert
  with check (owner_id = auth.uid());

create policy "cards_update_own"
  on public.cards for update
  using (owner_id = auth.uid());

create policy "cards_delete_own"
  on public.cards for delete
  using (owner_id = auth.uid());

-- ---------------- جدول الملفات ----------------
create table public.files (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  original_filename text not null,
  size_bytes bigint not null,
  mime_type text,
  storage_path text not null unique,
  created_at timestamptz not null default now()
);

alter table public.files enable row level security;

create policy "files_select_own_or_public_card"
  on public.files for select
  using (
    owner_id = auth.uid()
    or exists (select 1 from public.cards c where c.id = files.card_id and c.visibility = 'public')
  );

create policy "files_insert_own"
  on public.files for insert
  with check (
    owner_id = auth.uid()
    and exists (select 1 from public.cards c where c.id = card_id and c.owner_id = auth.uid())
  );

create policy "files_delete_own"
  on public.files for delete
  using (owner_id = auth.uid());

-- ---------------- دالة: هل ملف التخزين ده مسموح تقراه؟ ----------------
-- بتشتغل بصلاحيات أعلى (security definer) عشان تقدر تتحقق من كروت
-- "unlisted" برضه وهي مش ظاهرة أصلاً في الصلاحيات العادية لجدول cards
create function public.file_storage_accessible(p_storage_path text)
returns boolean
language sql
security definer set search_path = public
as $$
  select exists (
    select 1 from public.files f
    join public.cards c on c.id = f.card_id
    where f.storage_path = p_storage_path
      and (c.owner_id = auth.uid() or c.visibility in ('public','unlisted'))
  );
$$;

-- ---------------- دالة: جلب كارت مشترك برابط (unlisted/public) ----------------
-- المسار الوحيد للوصول لبيانات كارت unlisted — الجدول نفسه ما يسمحش
-- بقراءته عامة عشان ميبقاش قابل للحصر (enumeration)
create function public.get_shared_card(p_token uuid)
returns json
language plpgsql
security definer set search_path = public
as $$
declare
  result json;
begin
  select json_build_object(
    'card', json_build_object(
      'id', c.id, 'name', c.name, 'description', c.description,
      'allow_download', c.allow_download, 'visibility', c.visibility
    ),
    'files', coalesce((
      select json_agg(json_build_object(
        'id', f.id, 'name', f.name, 'size_bytes', f.size_bytes,
        'mime_type', f.mime_type, 'storage_path', f.storage_path
      ) order by f.created_at)
      from public.files f where f.card_id = c.id
    ), '[]'::json)
  ) into result
  from public.cards c
  where c.share_token = p_token and c.visibility in ('unlisted','public');

  return result;
end;
$$;

grant execute on function public.get_shared_card(uuid) to anon, authenticated;

-- ---------------- Storage bucket للملفات ----------------
-- خاص (public=false) — التحكم في القراءة كله عن طريق RLS تحت، مش عن طريق
-- خاصية "public bucket" العامة
insert into storage.buckets (id, name, public)
values ('study-files', 'study-files', false)
on conflict (id) do nothing;

create policy "storage_select"
  on storage.objects for select
  using (bucket_id = 'study-files' and public.file_storage_accessible(name));

create policy "storage_insert_own"
  on storage.objects for insert
  with check (bucket_id = 'study-files' and owner = auth.uid());

create policy "storage_delete_own"
  on storage.objects for delete
  using (bucket_id = 'study-files' and owner = auth.uid());


-- ############################################################
-- من ملف: schema_03_admin.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 3: صلاحية الأدمن + إحصائيات متقدمة
-- شغّل بعد schema.sql و schema_02_cards.sql — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- جدول الأدمن ----------------
-- ماله ولا policy قراءة/كتابة للكلاينت خالص — تضيف أدمن جديد يدويًا من
-- SQL Editor بس (مش من واجهة الموقع)، عشان محدش يقدر يرفّع نفسه أدمن
-- عن طريق باغ أو ثغرة في الكود.
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;

create function public.is_admin()
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists(select 1 from public.admins where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated, anon;

-- بعد ما تشغّل الملف، اعمل نفسك أدمن بسطر زي ده (غيّر الإيميل الداخلي
-- بتاعك؛ لو اسم المستخدم بتاعك "ahmed" يبقى ahmed@mektabty.local):
-- insert into public.admins (user_id)
-- select id from auth.users where email = 'ahmed@mektabty.local';

-- ---------------- بيانات خاصة لكل مستخدم (مش عامة زي profiles) ----------------
create table public.profile_private (
  id uuid primary key references auth.users(id) on delete cascade,
  gender text check (gender in ('male','female')),
  last_seen_at timestamptz
);
alter table public.profile_private enable row level security;

create policy "profile_private_self_or_admin_read"
  on public.profile_private for select
  using (id = auth.uid() or public.is_admin());

create policy "profile_private_self_update"
  on public.profile_private for update
  using (id = auth.uid());

create function public.handle_new_user_private()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profile_private (id, gender, last_seen_at)
  values (new.id, new.raw_user_meta_data ->> 'gender', now());
  return new;
end;
$$;

create trigger on_auth_user_created_private
  after insert on auth.users
  for each row execute procedure public.handle_new_user_private();

-- المستخدم بيستدعيها كل شوية وهو فاتح الموقع عشان نعرف "مين داخل دلوقتي"
create function public.touch_last_seen()
returns void
language sql security definer set search_path = public
as $$
  update public.profile_private set last_seen_at = now() where id = auth.uid();
$$;
grant execute on function public.touch_last_seen() to authenticated;

-- ---------------- سجل تسجيلات الدخول ----------------
create table public.login_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.login_events enable row level security;

create policy "login_events_insert_self"
  on public.login_events for insert
  with check (user_id = auth.uid());

create policy "login_events_select_admin"
  on public.login_events for select
  using (public.is_admin());

-- ---------------- مشاهدات روابط المشاركة ----------------
create table public.card_share_views (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  owner_id uuid,
  viewed_at timestamptz not null default now()
);
alter table public.card_share_views enable row level security;

-- owner_id بيتحسب من الكارت نفسه سيرفر-سايد، مش من قيمة بيبعتها الكلاينت
create function public.set_share_view_owner()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  select owner_id into new.owner_id from public.cards where id = new.card_id;
  return new;
end;
$$;
create trigger before_share_view_insert
  before insert on public.card_share_views
  for each row execute procedure public.set_share_view_owner();

create policy "share_views_insert_anyone"
  on public.card_share_views for insert
  with check (
    exists (select 1 from public.cards c where c.id = card_id and c.visibility in ('public','unlisted'))
  );

create policy "share_views_select_owner_or_admin"
  on public.card_share_views for select
  using (owner_id = auth.uid() or public.is_admin());

-- ---------------- دوال إحصائيات الأدمن ----------------

-- كل اللي دخلوا في يوم معيّن + هل كانوا "عائدين" (دخلوا قبل كده يوم تاني)
create function public.admin_get_day_logins(p_day date)
returns json
language plpgsql security definer set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;

  select coalesce(json_agg(json_build_object(
    'user_id', le.user_id,
    'username', p.username,
    'display_name', p.display_name,
    'gender', pp.gender,
    'login_at', le.created_at,
    'is_returning', (
      select count(distinct date(le2.created_at)) > 1
      from public.login_events le2
      where le2.user_id = le.user_id and le2.created_at <= le.created_at
    )
  ) order by le.created_at), '[]'::json) into result
  from public.login_events le
  join public.profiles p on p.id = le.user_id
  left join public.profile_private pp on pp.id = le.user_id
  where date(le.created_at) = p_day;

  return result;
end;
$$;
grant execute on function public.admin_get_day_logins(date) to authenticated;

-- ملخص رقمي لنفس اليوم: إجمالي الدخول، مستخدمين مختلفين، ذكور/إناث، مشاهدات مشاركة
create function public.admin_get_day_summary(p_day date)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  logins_total int; uniq_users int; male_count int; female_count int; shares_total int;
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;

  select count(*), count(distinct le.user_id) into logins_total, uniq_users
  from public.login_events le where date(le.created_at) = p_day;

  select count(*) filter (where pp.gender = 'male'),
         count(*) filter (where pp.gender = 'female')
  into male_count, female_count
  from public.login_events le
  join public.profile_private pp on pp.id = le.user_id
  where date(le.created_at) = p_day;

  select count(*) into shares_total
  from public.card_share_views where date(viewed_at) = p_day;

  return json_build_object(
    'logins_total', coalesce(logins_total, 0),
    'unique_users', coalesce(uniq_users, 0),
    'male', coalesce(male_count, 0),
    'female', coalesce(female_count, 0),
    'share_views', coalesce(shares_total, 0)
  );
end;
$$;
grant execute on function public.admin_get_day_summary(date) to authenticated;

-- مين "داخل" دلوقتي فعليًا (آخر ظهور خلال 5 دقايق)
create function public.admin_get_online_now()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'user_id', p.id, 'username', p.username,
      'display_name', p.display_name, 'last_seen_at', pp.last_seen_at
    ) order by pp.last_seen_at desc)
    from public.profile_private pp
    join public.profiles p on p.id = pp.id
    where pp.last_seen_at > now() - interval '5 minutes'
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_online_now() to authenticated;

-- ---------------- إشعارات عامة (تظهر لكل زوار الموقع) ----------------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;

create policy "notifications_read"
  on public.notifications for select
  using (active = true or public.is_admin());

create policy "notifications_admin_insert"
  on public.notifications for insert
  with check (public.is_admin());

create policy "notifications_admin_update"
  on public.notifications for update
  using (public.is_admin());

create policy "notifications_admin_delete"
  on public.notifications for delete
  using (public.is_admin());


-- ############################################################
-- من ملف: schema_04_extras.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 4: جدولة الإشعارات + نظام الموافقة على المشاركة
-- شغّل بعد الملفات التلاتة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- جدولة واستهداف الإشعارات ----------------
alter table public.notifications
  add column target_gender text not null default 'all' check (target_gender in ('all','male','female')),
  add column start_date date not null default current_date,
  add column days_duration int not null default 1 check (days_duration > 0),
  add column send_hour int not null default 0 check (send_hour between 0 and 23),
  add column send_minute int not null default 0 check (send_minute between 0 and 59);

-- ---------------- إعدادات عامة للموقع (صف واحد بس) ----------------
create table public.site_settings (
  id boolean primary key default true check (id),
  auto_approve_shares boolean not null default true
);
insert into public.site_settings (id, auto_approve_shares) values (true, true);
alter table public.site_settings enable row level security;

create policy "site_settings_public_read"
  on public.site_settings for select
  using (true);

create policy "site_settings_admin_update"
  on public.site_settings for update
  using (public.is_admin());

-- ---------------- موافقة الأدمن على مشاركة البطاقات ----------------
alter table public.cards add column approved boolean not null default true;

-- كل مرة تتغيّر فيها بطاقة، approved بتتحسب سيرفر-سايد دايمًا —
-- مش من قيمة بيبعتها الكلاينت، عشان محدش يقدر يوافق لنفسه
create function public.enforce_card_approval()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare auto_ok boolean;
begin
  if new.visibility = 'private' then
    new.approved := true;
  elsif public.is_admin() then
    new.approved := true;
  else
    select auto_approve_shares into auto_ok from public.site_settings limit 1;
    new.approved := coalesce(auto_ok, true);
  end if;
  return new;
end;
$$;

create trigger before_card_write
  before insert or update on public.cards
  for each row execute procedure public.enforce_card_approval();

-- تحديث قاعدة قراءة الكروت: البطاقة العامة لازم تكون approved كمان
drop policy "cards_select_own_or_public" on public.cards;
create policy "cards_select_own_or_public"
  on public.cards for select
  using (owner_id = auth.uid() or public.is_admin() or (visibility = 'public' and approved));

-- تحديث دالة الوصول لملفات الـStorage نفس الشرط
create or replace function public.file_storage_accessible(p_storage_path text)
returns boolean
language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.files f
    join public.cards c on c.id = f.card_id
    where f.storage_path = p_storage_path
      and (c.owner_id = auth.uid() or public.is_admin() or (c.visibility in ('public','unlisted') and c.approved))
  );
$$;

-- تحديث دالة رابط المشاركة نفس الشرط
create or replace function public.get_shared_card(p_token uuid)
returns json
language plpgsql security definer set search_path = public
as $$
declare result json;
begin
  select json_build_object(
    'card', json_build_object(
      'id', c.id, 'name', c.name, 'description', c.description,
      'allow_download', c.allow_download, 'visibility', c.visibility
    ),
    'files', coalesce((
      select json_agg(json_build_object(
        'id', f.id, 'name', f.name, 'size_bytes', f.size_bytes,
        'mime_type', f.mime_type, 'storage_path', f.storage_path
      ) order by f.created_at)
      from public.files f where f.card_id = c.id
    ), '[]'::json)
  ) into result
  from public.cards c
  where c.share_token = p_token and c.visibility in ('unlisted','public') and c.approved;

  return result;
end;
$$;
grant execute on function public.get_shared_card(uuid) to anon, authenticated;

-- ---------------- صلاحيات إضافية للأدمن (مراجعة/حذف بطاقات أي مستخدم) ----------------
create policy "cards_delete_admin"
  on public.cards for delete
  using (public.is_admin());

create policy "files_select_admin"
  on public.files for select
  using (public.is_admin());

create policy "storage_delete_admin"
  on storage.objects for delete
  using (bucket_id = 'study-files' and public.is_admin());

-- ---------------- دوال المراجعة ----------------
create function public.admin_get_pending_cards()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'id', c.id, 'name', c.name, 'description', c.description,
      'visibility', c.visibility, 'owner_username', p.username,
      'owner_display_name', p.display_name, 'created_at', c.created_at
    ) order by c.created_at)
    from public.cards c
    join public.profiles p on p.id = c.owner_id
    where c.approved = false
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_pending_cards() to authenticated;

create function public.admin_approve_card(p_card_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  update public.cards set approved = true where id = p_card_id;
end;
$$;
grant execute on function public.admin_approve_card(uuid) to authenticated;


-- ############################################################
-- من ملف: schema_05_contact.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 5: "تواصل معنا" (استفسار / مقترح / شكوى)
-- شغّل بعد الملفات الأربعة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

create table public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('inquiry', 'suggestion', 'complaint')),
  message text not null,
  contact_name text,
  user_id uuid references auth.users(id) on delete set null,
  status text not null default 'new' check (status in ('new', 'resolved')),
  created_at timestamptz not null default now()
);
alter table public.contact_messages enable row level security;

-- user_id بيتحسب من الجلسة نفسها سيرفر-سايد، مش من قيمة يبعتها الكلاينت
create function public.set_contact_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.user_id := auth.uid();
  return new;
end;
$$;
create trigger before_contact_insert
  before insert on public.contact_messages
  for each row execute procedure public.set_contact_user();

-- أي حد (حتى غير مسجل دخول) يقدر يبعت رسالة
create policy "contact_insert_anyone"
  on public.contact_messages for insert
  with check (true);

-- الأدمن بس اللي يشوف/يعدّل/يمسح الرسائل
create policy "contact_select_admin"
  on public.contact_messages for select
  using (public.is_admin());

create policy "contact_update_admin"
  on public.contact_messages for update
  using (public.is_admin());

create policy "contact_delete_admin"
  on public.contact_messages for delete
  using (public.is_admin());


-- ############################################################
-- من ملف: schema_06_cards_extras.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 6: تعليقات + إبلاغ + حد أقصى للبطاقات
-- شغّل بعد الملفات الخمسة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- حد أقصى لعدد البطاقات لكل مستخدم (0 = بدون حد) ----------------
alter table public.site_settings add column max_cards_per_user int not null default 0;

create function public.enforce_card_limit()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare max_allowed int; current_count int;
begin
  if tg_op = 'INSERT' and not public.is_admin() then
    select max_cards_per_user into max_allowed from public.site_settings limit 1;
    if max_allowed > 0 then
      select count(*) into current_count from public.cards where owner_id = new.owner_id;
      if current_count >= max_allowed then
        raise exception 'وصلت للحد الأقصى المسموح به من البطاقات (%)', max_allowed;
      end if;
    end if;
  end if;
  return new;
end;
$$;
create trigger before_card_insert_limit
  before insert on public.cards
  for each row execute procedure public.enforce_card_limit();

-- ---------------- تعليقات على البطاقات العامة/برابط ----------------
create table public.card_comments (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now()
);
alter table public.card_comments enable row level security;

create policy "comments_select_if_card_visible"
  on public.card_comments for select
  using (
    exists (
      select 1 from public.cards c where c.id = card_id
      and (c.owner_id = auth.uid() or public.is_admin() or (c.visibility in ('public','unlisted') and c.approved))
    )
  );

create policy "comments_insert_logged_in"
  on public.card_comments for insert
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.cards c where c.id = card_id and c.visibility in ('public','unlisted') and c.approved)
  );

create policy "comments_delete_own_or_card_owner_or_admin"
  on public.card_comments for delete
  using (
    user_id = auth.uid()
    or public.is_admin()
    or exists (select 1 from public.cards c where c.id = card_id and c.owner_id = auth.uid())
  );

-- ---------------- الإبلاغ عن بطاقة ----------------
create table public.card_reports (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  reporter_id uuid references auth.users(id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);
alter table public.card_reports enable row level security;

create function public.set_report_reporter()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.reporter_id := auth.uid();
  return new;
end;
$$;
create trigger before_report_insert
  before insert on public.card_reports
  for each row execute procedure public.set_report_reporter();

create policy "reports_insert_anyone"
  on public.card_reports for insert
  with check (
    exists (select 1 from public.cards c where c.id = card_id and c.visibility in ('public','unlisted') and c.approved)
  );

create policy "reports_select_admin"
  on public.card_reports for select
  using (public.is_admin());

create policy "reports_delete_admin"
  on public.card_reports for delete
  using (public.is_admin());

create function public.admin_get_reported_cards()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'report_id', r.id, 'card_id', c.id, 'card_name', c.name,
      'reason', r.reason, 'reported_at', r.created_at,
      'owner_username', p.username
    ) order by r.created_at desc)
    from public.card_reports r
    join public.cards c on c.id = r.card_id
    join public.profiles p on p.id = c.owner_id
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_reported_cards() to authenticated;

create function public.admin_dismiss_report(p_report_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  delete from public.card_reports where id = p_report_id;
end;
$$;
grant execute on function public.admin_dismiss_report(uuid) to authenticated;


-- ############################################################
-- من ملف: schema_07_notif_extras.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 7: ربط الإشعار بكورس + إحصائيات المشاهدة
-- شغّل بعد الملفات الستة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

alter table public.notifications
  add column link_course_id text,
  add column seen_count int not null default 0,
  add column dismissed_count int not null default 0;

-- بنسمح لأي حد (حتى غير مسجل دخول) يزوّد العدّاد ده بس — مفيش أي قراءة
-- أو تعديل تاني مسموح من غير أدمن
create function public.track_notification_view(p_id uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.notifications set seen_count = seen_count + 1 where id = p_id;
$$;
grant execute on function public.track_notification_view(uuid) to anon, authenticated;

create function public.track_notification_dismiss(p_id uuid)
returns void
language sql security definer set search_path = public
as $$
  update public.notifications set dismissed_count = dismissed_count + 1 where id = p_id;
$$;
grant execute on function public.track_notification_dismiss(uuid) to anon, authenticated;


-- ############################################################
-- من ملف: schema_08_stats_extras.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 8: اتجاه الدخول + أكتر المحتوى مشاهدة
-- شغّل بعد الملفات السبعة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- تتبّع فتح الكورسات (الكورسات نفسها في sites.json مش هنا) ----------------
create table public.course_views (
  id uuid primary key default gen_random_uuid(),
  course_id text not null,
  viewed_at timestamptz not null default now()
);
alter table public.course_views enable row level security;

create policy "course_views_insert_anyone"
  on public.course_views for insert
  with check (true);

create policy "course_views_select_admin"
  on public.course_views for select
  using (public.is_admin());

-- ---------------- اتجاه الدخول على مدار كذا يوم ----------------
create function public.admin_get_login_trend(p_days int)
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object('day', d.day, 'count', coalesce(c.cnt, 0)) order by d.day)
    from generate_series(current_date - (p_days - 1), current_date, interval '1 day') as d(day)
    left join (
      select date(created_at) as day, count(*) as cnt
      from public.login_events
      where created_at >= current_date - (p_days - 1)
      group by date(created_at)
    ) c on c.day = d.day::date
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_login_trend(int) to authenticated;

-- ---------------- أكتر البطاقات مشاهدة ----------------
create function public.admin_get_top_cards(p_limit int)
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object('card_name', c.name, 'owner_username', p.username, 'views', v.cnt) order by v.cnt desc)
    from (
      select card_id, count(*) as cnt from public.card_share_views group by card_id order by count(*) desc limit p_limit
    ) v
    join public.cards c on c.id = v.card_id
    join public.profiles p on p.id = c.owner_id
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_top_cards(int) to authenticated;

-- ---------------- أكتر الكورسات فتحًا ----------------
create function public.admin_get_top_courses(p_limit int)
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object('course_id', course_id, 'views', cnt) order by cnt desc)
    from (
      select course_id, count(*) as cnt from public.course_views group by course_id order by count(*) desc limit p_limit
    ) t
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_top_courses(int) to authenticated;


-- ############################################################
-- من ملف: schema_09_users_extras.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 9: ملاحظات الأدمن على المستخدمين + تعطيل مؤقت
-- شغّل بعد الملفات التمانية اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- ملاحظة خاصة بالأدمن (المستخدم نفسه مايشوفهاش أبدًا) ----------------
create table public.admin_user_notes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  note text,
  updated_at timestamptz not null default now()
);
alter table public.admin_user_notes enable row level security;

create policy "admin_notes_admin_only"
  on public.admin_user_notes for all
  using (public.is_admin())
  with check (public.is_admin());

-- ---------------- تعطيل مؤقت للحساب ----------------
alter table public.profile_private add column disabled boolean not null default false;

-- المستخدم العادي يقدر يعدّل صف نفسه (زي last_seen_at) لكن عمود disabled
-- محمي: أي تغيير فيه من غير أدمن بيتلغى تلقائيًا
create function public.protect_disabled_field()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.disabled is distinct from old.disabled and not public.is_admin() then
    new.disabled := old.disabled;
  end if;
  return new;
end;
$$;
create trigger before_profile_private_update
  before update on public.profile_private
  for each row execute procedure public.protect_disabled_field();

-- ⚠️ ملحوظة صراحة: ده تعطيل "على مستوى التطبيق" مش حظر حقيقي من Supabase
-- Auth نفسه (ده محتاج service_role key اللي متعمدين متحطوش في كود
-- الموقع لأسباب أمنية). يعني: الحساب فعليًا لسه يقدر يعمل تسجيل دخول
-- ناجح في Supabase، لكن كود الموقع بيكتشف إنه معطّل فورًا بعد الدخول
-- ويسجّل خروجه تلقائيًا برسالة واضحة. كافي 99% من الحالات العادية.


-- ############################################################
-- من ملف: schema_10_chat_purchase.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 10: شات مباشر مع الأدمن + طلبات شراء المشروع
-- شغّل بعد الملفات التسعة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- شات المستخدم مع الأدمن ----------------
create table public.admin_chat_messages (
  id uuid primary key default gen_random_uuid(),
  thread_user_id uuid not null references auth.users(id) on delete cascade,
  sender text not null check (sender in ('user', 'admin')),
  message text not null,
  created_at timestamptz not null default now(),
  read boolean not null default false
);
alter table public.admin_chat_messages enable row level security;

-- sender وthread_user_id بيتحددوا سيرفر-سايد حسب هوية اللي بيبعت فعليًا،
-- مش من أي قيمة يبعتها الكلاينت — يمنع أي حد يتظاهر إنه أدمن أو يدخل
-- على شات حد تاني
create function public.set_chat_sender()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if public.is_admin() and new.thread_user_id is not null and new.thread_user_id != auth.uid() then
    new.sender := 'admin';
  else
    new.sender := 'user';
    new.thread_user_id := auth.uid();
  end if;
  return new;
end;
$$;
create trigger before_chat_insert
  before insert on public.admin_chat_messages
  for each row execute procedure public.set_chat_sender();

create policy "chat_select_own_or_admin"
  on public.admin_chat_messages for select
  using (thread_user_id = auth.uid() or public.is_admin());

create policy "chat_insert_own_or_admin"
  on public.admin_chat_messages for insert
  with check (thread_user_id = auth.uid() or public.is_admin());

create policy "chat_update_mark_read"
  on public.admin_chat_messages for update
  using (thread_user_id = auth.uid() or public.is_admin());

-- قائمة محادثات الأدمن: آخر رسالة + عدد الرسايل الغير مقروءة لكل مستخدم
create function public.admin_get_chat_threads()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(t order by (t->>'last_at') desc) from (
      select json_build_object(
        'user_id', m.thread_user_id,
        'username', p.username,
        'display_name', p.display_name,
        'last_message', (select message from public.admin_chat_messages m2 where m2.thread_user_id = m.thread_user_id order by created_at desc limit 1),
        'last_at', (select created_at from public.admin_chat_messages m2 where m2.thread_user_id = m.thread_user_id order by created_at desc limit 1),
        'unread', (select count(*) from public.admin_chat_messages m3 where m3.thread_user_id = m.thread_user_id and m3.sender = 'user' and m3.read = false)
      ) t
      from (select distinct thread_user_id from public.admin_chat_messages) m
      join public.profiles p on p.id = m.thread_user_id
    ) x
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_chat_threads() to authenticated;

-- ---------------- طلبات شراء المشروع ----------------
create table public.purchase_inquiries (
  id uuid primary key default gen_random_uuid(),
  buyer_type text not null check (buyer_type in ('individual', 'company')),
  email text not null,
  phone text,
  message text not null,
  user_id uuid references auth.users(id) on delete set null,
  status text not null default 'new' check (status in ('new', 'resolved')),
  created_at timestamptz not null default now()
);
alter table public.purchase_inquiries enable row level security;

create function public.set_purchase_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.user_id := auth.uid();
  return new;
end;
$$;
create trigger before_purchase_insert
  before insert on public.purchase_inquiries
  for each row execute procedure public.set_purchase_user();

create policy "purchase_insert_anyone"
  on public.purchase_inquiries for insert
  with check (true);

create policy "purchase_select_admin"
  on public.purchase_inquiries for select
  using (public.is_admin());

create policy "purchase_update_admin"
  on public.purchase_inquiries for update
  using (public.is_admin());

create policy "purchase_delete_admin"
  on public.purchase_inquiries for delete
  using (public.is_admin());


-- ############################################################
-- من ملف: schema_11_final.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 11 (الأخيرة): سجل النشاط + وضع الصيانة + سلة مهملات البطاقات
-- شغّل بعد الملفات العشرة اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- سجل نشاط الأدمن ----------------
create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  details jsonb,
  created_at timestamptz not null default now()
);
alter table public.audit_log enable row level security;

create function public.set_audit_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.admin_id := auth.uid();
  return new;
end;
$$;
create trigger before_audit_insert
  before insert on public.audit_log
  for each row execute procedure public.set_audit_admin();

create policy "audit_insert_admin"
  on public.audit_log for insert
  with check (public.is_admin());

create policy "audit_select_admin"
  on public.audit_log for select
  using (public.is_admin());

-- ---------------- وضع الصيانة ----------------
alter table public.site_settings
  add column maintenance_mode boolean not null default false,
  add column maintenance_message text not null default 'الموقع تحت الصيانة حاليًا، هنرجع قريب.';

-- ---------------- سلة مهملات البطاقات (soft delete) ----------------
alter table public.cards add column deleted_at timestamptz;

create policy "cards_update_admin"
  on public.cards for update
  using (public.is_admin());

-- القراءة العادية (كل السياسات القديمة) لازم تستثني المحذوف مؤقتًا
drop policy "cards_select_own_or_public" on public.cards;
create policy "cards_select_own_or_public"
  on public.cards for select
  using (deleted_at is null and (owner_id = auth.uid() or public.is_admin() or (visibility = 'public' and approved)));

create or replace function public.file_storage_accessible(p_storage_path text)
returns boolean
language sql security definer set search_path = public
as $$
  select exists (
    select 1 from public.files f
    join public.cards c on c.id = f.card_id
    where f.storage_path = p_storage_path
      and c.deleted_at is null
      and (c.owner_id = auth.uid() or public.is_admin() or (c.visibility in ('public','unlisted') and c.approved))
  );
$$;

create or replace function public.get_shared_card(p_token uuid)
returns json
language plpgsql security definer set search_path = public
as $$
declare result json;
begin
  select json_build_object(
    'card', json_build_object(
      'id', c.id, 'name', c.name, 'description', c.description,
      'allow_download', c.allow_download, 'visibility', c.visibility
    ),
    'files', coalesce((
      select json_agg(json_build_object(
        'id', f.id, 'name', f.name, 'size_bytes', f.size_bytes,
        'mime_type', f.mime_type, 'storage_path', f.storage_path
      ) order by f.created_at)
      from public.files f where f.card_id = c.id
    ), '[]'::json)
  ) into result
  from public.cards c
  where c.share_token = p_token and c.visibility in ('unlisted','public') and c.approved and c.deleted_at is null;

  return result;
end;
$$;

-- طابور سلة المهملات — RPC بيتخطى فلتر "deleted_at is null" العادي
create function public.admin_get_trashed_cards()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'id', c.id, 'name', c.name, 'owner_username', p.username, 'deleted_at', c.deleted_at
    ) order by c.deleted_at desc)
    from public.cards c
    join public.profiles p on p.id = c.owner_id
    where c.deleted_at is not null
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_get_trashed_cards() to authenticated;

create function public.admin_restore_card(p_card_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  update public.cards set deleted_at = null where id = p_card_id;
end;
$$;
grant execute on function public.admin_restore_card(uuid) to authenticated;

-- تحديث دالتين قديمتين عشان يرجّعوا owner_id كمان (محتاجينه لإرسال رد جاهز في الشات)
create or replace function public.admin_get_pending_cards()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'id', c.id, 'name', c.name, 'description', c.description,
      'visibility', c.visibility, 'owner_id', c.owner_id, 'owner_username', p.username,
      'owner_display_name', p.display_name, 'created_at', c.created_at
    ) order by c.created_at)
    from public.cards c
    join public.profiles p on p.id = c.owner_id
    where c.approved = false and c.deleted_at is null
  ), '[]'::json);
end;
$$;

create or replace function public.admin_get_reported_cards()
returns json
language plpgsql security definer set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(json_build_object(
      'report_id', r.id, 'card_id', c.id, 'card_name', c.name, 'owner_id', c.owner_id,
      'reason', r.reason, 'reported_at', r.created_at,
      'owner_username', p.username
    ) order by r.created_at desc)
    from public.card_reports r
    join public.cards c on c.id = r.card_id
    join public.profiles p on p.id = c.owner_id
  ), '[]'::json);
end;
$$;

-- ############################################################
-- من ملف: schema_12_fixes.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 12: تصحيح باغين حقيقيين
-- شغّل بعد الملف الموحّد schema.sql — Supabase SQL Editor > New query > Run
-- ============================================================

-- ---------------- باغ 1: التعليقات كانت بتفشل تمامًا ----------------
-- جدول card_comments محتاج user_id (not null)، لكن مفيش trigger كان
-- بيحطه تلقائي، والكود في الموقع مابيبعتوش — يعني أي تعليق كان
-- هيفشل بسبب قيد "not null". الدالة دي بتحل المشكلة بنفس أسلوب باقي
-- الجداول (contact_messages, purchase_inquiries...)
create function public.set_comment_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  new.user_id := auth.uid();
  return new;
end;
$$;
create trigger before_comment_insert
  before insert on public.card_comments
  for each row execute procedure public.set_comment_user();

-- ---------------- باغ 2: تعديل بطاقة عامة موافَق عليها كان بيرجّعها معلّقة ----------------
-- الدالة القديمة كانت بتعيد حساب "approved" مع أي تحديث (حتى تعديل
-- بسيط زي وصف أو إذن تحميل)، فلو الموافقة التلقائية مقفولة، أي تعديل
-- على بطاقة عامة شغالة بالفعل كان بيوقفها فجأة في انتظار المراجعة
-- تاني من غير أي سبب حقيقي. النسخة دي بتفرّق بين:
-- - إنشاء بطاقة جديدة / تحويلها لأول مرة من خاصة لعامة → يطبّق قاعدة
--   الموافقة التلقائية
-- - أي تعديل تاني على بطاقة عامة موجودة بالفعل → يحافظ على حالة
--   الموافقة الحالية زي ما هي
create or replace function public.enforce_card_approval()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare auto_ok boolean;
begin
  if new.visibility = 'private' then
    new.approved := true;
  elsif public.is_admin() then
    -- الأدمن بيتحكم في approved مباشرة (زي admin_approve_card) —
    -- سيبها زي ما هي من غير تدخّل
    null;
  elsif tg_op = 'INSERT' then
    select auto_approve_shares into auto_ok from public.site_settings limit 1;
    new.approved := coalesce(auto_ok, true);
  elsif tg_op = 'UPDATE' and old.visibility = 'private' and new.visibility != 'private' then
    -- أول مرة تتحول لعامة/برابط — يطبّق قاعدة الموافقة التلقائية
    select auto_approve_shares into auto_ok from public.site_settings limit 1;
    new.approved := coalesce(auto_ok, true);
  else
    -- أي تعديل تاني على بطاقة عامة موجودة بالفعل — سيب حالة الموافقة زي ما هي
    new.approved := old.approved;
  end if;
  return new;
end;
$$;

-- ---------------- باغ 3: أعمدة قد تفشل صامتة في الموقع ----------------
-- profile_private.id وcard_comments.user_id بيشيروا لـauth.users بس،
-- مش لـprofiles مباشرة — يعني لما الكود في الموقع بيطلب "هات المستخدم
-- مع بروفايله الخاص/تعليقاته" في استعلام واحد (مثلاً
-- profiles.select('...profile_private(...)')، أو
-- card_comments.select('...profiles(...)'))، PostgREST محتاج علاقة
-- مباشرة (foreign key) بين الجدولين بالظبط عشان يعرف يربطهم — والعلاقة
-- الحالية غير مباشرة (كل واحد بيشاور على auth.users لوحده). ده ممكن
-- يخلي الاستعلام يفشل أو يرجّع بيانات ناقصة صامتة. الحل: نضيف foreign
-- key إضافي مباشر لجدول profiles (آمن 100% لأن كل صف موجود أصلاً في
-- الاتنين في نفس اللحظة عن طريق الـtriggers الموجودة).
alter table public.profile_private
  add constraint profile_private_profiles_fk foreign key (id) references public.profiles(id) on delete cascade;

alter table public.card_comments
  add constraint card_comments_profiles_fk foreign key (user_id) references public.profiles(id) on delete cascade;

-- ############################################################
-- من ملف: schema_13_community.sql
-- ############################################################
-- ============================================================
-- مكتبتي — الخطوة 13: قسم "ملفات المجتمع" (تصفح عام لبطاقات المستخدمين)
-- شغّل بعد كل الملفات اللي قبله — Supabase SQL Editor > New query > Run
-- ============================================================

-- ربط مباشر بين cards وprofiles (نفس فكرة التصحيح اللي عملناه قبل كده
-- لـ profile_private وcard_comments) — عشان استعلام "هات كل البطاقات
-- العامة مع اسم صاحب كل واحدة" يشتغل بشكل موثوق من غير لف على جداول تانية
alter table public.cards
  add constraint cards_owner_profiles_fk foreign key (owner_id) references public.profiles(id);

-- ملحوظة: مفيش داعي لأي RLS جديدة — الصلاحية الحالية
-- "cards_select_own_or_public" أصلاً بتسمح لأي حد (حتى غير مسجل دخول)
-- يشوف أي بطاقة (visibility='public' and approved=true)، وهي بالظبط
-- الشرط اللي هنستخدمه في صفحة "ملفات المجتمع" الجديدة.

-- ============================================================
-- مكتبتي — قسم "ملفات المجتمع" (ملفات مستضافة فعليًا على GitHub)
-- شغّله مرة واحدة في: Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================
-- ملحوظة مهمة: ده ملف SQL بيعمل بس الجدول + الصلاحيات (RLS) اللي
-- الموقع محتاجها عشان يعرض "ملفات المجتمع". التوكن بتاع GitHub نفسه
-- ومنطق الرفع الفعلي على GitHub مش هنا خالص — دول في ملف الـEdge
-- Function المنفصل (publish-to-community/index.ts) اللي هيتنشر من
-- تبويب Functions في لوحة Supabase، مش من هنا. الـSQL مايقدرش يعمل
-- طلبات HTTP لـGitHub أو يتعامل مع base64 لملفات كبيرة بشكل موثوق،
-- فمش المكان الصح للتوكن أو لمنطق الرفع.
-- ============================================================

drop table if exists public.community_files cascade;

-- الجدول ده هو "فهرس" سريع لكل ملف اتنشر فعليًا على GitHub — الملف
-- الحقيقي (البايتات) عايش على GitHub، والصف هنا بس بيقول "فين" ورابط
-- تنزيله المباشر، عشان الموقع يقدر يعرض القائمة بسرعة من غير ما يكلم
-- GitHub API في كل زيارة (وده كمان بيتفادى حدود GitHub Rate Limit).
create table public.community_files (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  file_id uuid references public.files(id) on delete set null,
  owner_id uuid not null references auth.users(id) on delete cascade,
  owner_display_name text,
  card_name text not null,
  file_name text not null,
  size_bytes bigint,
  mime_type text,
  github_path text not null,
  download_url text not null,
  published_at timestamptz not null default now(),
  unique (card_id, file_name)
);

alter table public.community_files enable row level security;

-- أي حد (حتى غير مسجل دخول) يقدر يشوف القائمة — ده بالظبط قسم عام
-- زي "ملفات المجتمع" المفروض يكون
create policy "community_files_public_read"
  on public.community_files for select
  using (true);

-- ملحوظة مقصودة: مفيش أي policy لـinsert/update/delete هنا خالص —
-- لا لـanon ولا لـauthenticated. الكتابة الوحيدة المسموحة في الجدول
-- ده بتحصل من جوه الـEdge Function باستخدام الـservice role key بتاعها
-- (وده بيتخطى RLS تلقائيًا زي ما هو مصمم في Supabase). يعني حتى لو
-- حد حاول يزوّر "نشر" من كونسول المتصفح مباشرة، مش هيقدر — لازم
-- يعدّي فعليًا من الـFunction اللي بتتأكد من الملكية والموافقة الأول.

-- ============================================================
-- مكتبتي — إضافة على "ملفات المجتمع": أقسام + مميز + عداد تحميل
-- شغّله بعد community-files.sql (إضافة عليه مش بديل عنه)
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

alter table public.community_files
  add column if not exists categories text[] not null default '{}',
  add column if not exists featured boolean not null default false,
  add column if not exists download_count integer not null default 0;

-- ------------------------------------------------------------
-- "مميز" — بيحدده الأدمن بس، مش المستخدم العادي ولا حتى صاحب
-- الملف نفسه. الكتابة هنا مسموحة للأدمن فقط عن طريق is_admin()
-- (نفس الدالة المستخدمة في باقي أجزاء الموقع للتحقق من الأدمن)
-- ------------------------------------------------------------
drop policy if exists "community_files_admin_update" on public.community_files;
create policy "community_files_admin_update"
  on public.community_files for update
  using (public.is_admin())
  with check (public.is_admin());

-- ------------------------------------------------------------
-- عداد التحميل — بيتزوّد لأي حد (حتى غير مسجل دخول) لما يضغط
-- "تحميل" فعليًا، لكن عن طريق دالة محصورة بس في زيادة الرقم +1،
-- مش UPDATE مباشر مفتوح (عشان محدش يقدر يعدّل أي عمود تاني زي
-- categories أو featured من نفس الطريق دي)
-- ------------------------------------------------------------
create or replace function public.increment_community_download(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.community_files set download_count = download_count + 1 where id = p_id;
end;
$$;
grant execute on function public.increment_community_download(uuid) to anon, authenticated;

-- ============================================================
-- مكتبتي — "المفضلة" و"أشاهدها لاحقًا" لملفات المجتمع
-- شغّله بعد community-files.sql و community-categories.sql
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

drop table if exists public.community_saved cascade;

-- صف واحد = مستخدم معين حط ملف معين في "مفضلة" أو "أشاهدها لاحقًا".
-- ممكن يكون الملف في الاتنين في نفس الوقت (صفين منفصلين)
create table public.community_saved (
  user_id uuid not null references auth.users(id) on delete cascade,
  file_id uuid not null references public.community_files(id) on delete cascade,
  save_type text not null check (save_type in ('favorite', 'later')),
  created_at timestamptz not null default now(),
  primary key (user_id, file_id, save_type)
);

alter table public.community_saved enable row level security;

-- كل مستخدم يشوف ويضيف ويمسح بس الصفوف بتاعته هو
create policy "community_saved_owner_all"
  on public.community_saved for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ============================================================
-- مكتبتي — مراجعة بعدية لملفات المجتمع + تحكم كامل في الشات +
-- متابعة + إحصائية مساحة تخزين
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) مراجعة بعدية لملفات المجتمع
-- الملف بيتنشر فورًا (auto) وبيظهر للعامة على طول، وبعدين الأدمن
-- بيدخل ويراجع: يوافق (تأكيد)، يرفض (يختفي من العرض العام فورًا)،
-- أو يأجّل (يسيبه زي ما هو، يراجعه بعدين — مفيش تغيير فعلي، بس
-- زرار "تخطي" في واجهة الأدمن)
-- ------------------------------------------------------------
alter table public.community_files
  add column if not exists status text not null default 'pending' check (status in ('pending', 'approved', 'rejected'));

-- القراءة العامة بترجع بس الملفات اللي مش مرفوضة (pending أو approved).
-- الأدمن يشوف كل حاجة بما فيها المرفوضة (عشان يقدر يسترجعها)
drop policy if exists "community_files_public_read" on public.community_files;
create policy "community_files_public_read"
  on public.community_files for select
  using (status <> 'rejected');

drop policy if exists "community_files_admin_read_all" on public.community_files;
create policy "community_files_admin_read_all"
  on public.community_files for select
  using (public.is_admin());

-- الأدمن ينفعله يعدّل status (موافقة/رفض) بالإضافة لـfeatured
-- (نفس policy الموجودة أصلاً بتغطي التحديث، مفيش داعي نضيف واحدة تانية)

-- ------------------------------------------------------------
-- 2) تحكم كامل في محادثات الأدمن — مسح رسالة بعينها (حتى لو
-- المستخدم هو اللي بعتها) أو مسح المحادثة كاملة. الأدمن بس اللي
-- يقدر يمسح؛ المستخدم العادي ماينفعوش يمسح ولا رسالته هو حتى
-- ------------------------------------------------------------
drop policy if exists "chat_delete_admin_only" on public.admin_chat_messages;
create policy "chat_delete_admin_only"
  on public.admin_chat_messages for delete
  using (public.is_admin());

-- ------------------------------------------------------------
-- 3) متابعة قسم أو صاحب ملفات في "ملفات المجتمع"
-- ------------------------------------------------------------
drop table if exists public.community_follows cascade;
create table public.community_follows (
  user_id uuid not null references auth.users(id) on delete cascade,
  follow_type text not null check (follow_type in ('category', 'owner')),
  follow_value text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, follow_type, follow_value)
);
alter table public.community_follows enable row level security;
create policy "community_follows_owner_all"
  on public.community_follows for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ------------------------------------------------------------
-- 4) إحصائية مساحة التخزين — مين مستهلك مساحة قد إيه (لملفات
-- "ملفاتي"، اللي هي المساحة الفعلية المحجوزة في Supabase Storage)
-- ------------------------------------------------------------
create or replace function public.admin_storage_usage()
returns json
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then raise exception 'غير مسموح'; end if;
  return coalesce((
    select json_agg(t order by (t->>'total_bytes')::bigint desc) from (
      select json_build_object(
        'owner_id', f.owner_id,
        'username', p.username,
        'display_name', p.display_name,
        'file_count', count(*),
        'total_bytes', coalesce(sum(f.size_bytes), 0)
      ) t
      from public.files f
      join public.profiles p on p.id = f.owner_id
      group by f.owner_id, p.username, p.display_name
    ) x
  ), '[]'::json);
end;
$$;
grant execute on function public.admin_storage_usage() to authenticated;

-- ============================================================
-- مكتبتي — إشعارات حقيقية للمتابعة (قسم/ناشر) في ملفات المجتمع
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- صندوق إشعارات شخصي لكل مستخدم (مختلف عن جدول notifications
-- العام اللي بيستخدمه الأدمن للبث المجدول للجميع)
drop table if exists public.user_notifications cascade;
create table public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  link_url text,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.user_notifications enable row level security;

create policy "user_notifications_owner_select"
  on public.user_notifications for select
  using (auth.uid() = user_id);
create policy "user_notifications_owner_update"
  on public.user_notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
-- مفيش policy لـinsert لأي دور عادي — الإدراج بيحصل بس من الـtrigger
-- تحت (اللي بيشتغل بصلاحيات الجدول نفسه، مش المستخدم)

-- بيشتغل تلقائيًا كل ما ملف جديد يتنشر في ملفات المجتمع: بيدوّر على
-- كل حد متابع القسم(الأقسام) بتاعت الملف أو متابع صاحب الملف نفسه،
-- ويولّدلهم إشعار واحد لكل حد (حتى لو بيتابع أكتر من سبب)
create or replace function public.notify_followers_on_community_publish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_notifications (user_id, message, link_url)
  select distinct f.user_id,
    'في ملف جديد من "' || coalesce(new.owner_display_name, 'مستخدم') || '": ' || new.file_name,
    '?community=1'
  from public.community_follows f
  where (f.follow_type = 'owner' and f.follow_value = new.owner_id::text)
     or (f.follow_type = 'category' and f.follow_value = any(new.categories))
  -- مايبعتش إشعار للشخص نفسه لو بيتابع نفسه بالغلط
  and f.user_id <> new.owner_id;
  return new;
end;
$$;

drop trigger if exists trg_notify_followers_on_publish on public.community_files;
create trigger trg_notify_followers_on_publish
  after insert on public.community_files
  for each row execute function public.notify_followers_on_community_publish();

-- ============================================================
-- مكتبتي — معرّف عام لكل مستخدم + شارات + ترتيب عالمي
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) معرّف عام قصير لكل مستخدم (زي #A3F9K2) — يتولّد أوتوماتيك،
-- يستخدم للبحث عن أي حد والتواصل معاه من غير ما تعرف اسم مستخدمه
-- ------------------------------------------------------------
alter table public.profiles add column if not exists public_id text unique;

create or replace function public.generate_public_id()
returns text language plpgsql as $$
declare
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- من غير حروف/أرقام ملخبطة زي O/0 أو I/1
  result text := '';
  i int;
begin
  for i in 1..7 loop
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  end loop;
  return result;
end;
$$;

create or replace function public.set_public_id()
returns trigger language plpgsql as $$
declare
  candidate text;
  tries int := 0;
begin
  if new.public_id is not null then return new; end if;
  loop
    candidate := public.generate_public_id();
    exit when not exists (select 1 from public.profiles where public_id = candidate);
    tries := tries + 1;
    if tries > 30 then raise exception 'تعذّر توليد معرف فريد'; end if;
  end loop;
  new.public_id := candidate;
  return new;
end;
$$;

drop trigger if exists trg_set_public_id on public.profiles;
create trigger trg_set_public_id
  before insert on public.profiles
  for each row execute function public.set_public_id();

-- تعبئة المعرف لأي حساب قديم كان موجود قبل التعديل ده
do $$
declare
  r record;
  candidate text;
  tries int;
begin
  for r in select id from public.profiles where public_id is null loop
    tries := 0;
    loop
      candidate := public.generate_public_id();
      exit when not exists (select 1 from public.profiles where public_id = candidate);
      tries := tries + 1;
      if tries > 30 then exit; end if;
    end loop;
    update public.profiles set public_id = candidate where id = r.id;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) الشارات — بتتحسب وتتضاف أوتوماتيك، مش بتتحط يدوي
-- ------------------------------------------------------------
drop table if exists public.user_badges cascade;
create table public.user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_key text not null,
  earned_at timestamptz not null default now(),
  primary key (user_id, badge_key)
);
alter table public.user_badges enable row level security;
create policy "user_badges_public_read" on public.user_badges for select using (true);
-- مفيش insert policy — الإضافة بس من الدالة تحت (security definer)

create or replace function public.check_and_award_badges(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_files_count int;
  v_downloads_total bigint;
  v_featured_count int;
  v_followers_count int;
begin
  select count(*), coalesce(sum(download_count), 0)
    into v_files_count, v_downloads_total
    from public.community_files where owner_id = p_user_id;

  select count(*) into v_featured_count
    from public.community_files where owner_id = p_user_id and featured = true;

  select count(*) into v_followers_count
    from public.community_follows where follow_type = 'owner' and follow_value = p_user_id::text;

  if v_files_count >= 1 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'first_publish') on conflict do nothing;
  end if;
  if v_downloads_total >= 10 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'ten_downloads') on conflict do nothing;
  end if;
  if v_downloads_total >= 100 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'hundred_downloads') on conflict do nothing;
  end if;
  if v_downloads_total >= 1000 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'thousand_downloads') on conflict do nothing;
  end if;
  if v_featured_count >= 1 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'featured_creator') on conflict do nothing;
  end if;
  if v_followers_count >= 10 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'popular_creator') on conflict do nothing;
  end if;
  if v_files_count >= 10 then
    insert into public.user_badges (user_id, badge_key) values (p_user_id, 'ten_files') on conflict do nothing;
  end if;
end;
$$;

-- بتتفحص الشارات أوتوماتيك كل ما: ملف جديد يتنشر، عدد التحميلات
-- يتغيّر، الملف يتحط "مميز"، أو حد جديد يتابع
create or replace function public.trg_check_badges_on_community_files()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.check_and_award_badges(new.owner_id);
  return new;
end;
$$;
drop trigger if exists trg_badges_community_files on public.community_files;
create trigger trg_badges_community_files
  after insert or update of download_count, featured on public.community_files
  for each row execute function public.trg_check_badges_on_community_files();

create or replace function public.trg_check_badges_on_follow()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.follow_type = 'owner' then
    perform public.check_and_award_badges(new.follow_value::uuid);
  end if;
  return new;
end;
$$;
drop trigger if exists trg_badges_follow on public.community_follows;
create trigger trg_badges_follow
  after insert on public.community_follows
  for each row execute function public.trg_check_badges_on_follow();

-- ------------------------------------------------------------
-- 3) الترتيب العالمي — حسب إجمالي عدد التحميلات لكل ملفات المستخدم
-- (معيار موضوعي وموجود بالفعل، مش محتاج حساب جديد)
-- ------------------------------------------------------------
create or replace function public.get_user_rank(p_user_id uuid)
returns json language sql stable as $$
  with ranked as (
    select owner_id, coalesce(sum(download_count), 0) as total_downloads,
           rank() over (order by coalesce(sum(download_count), 0) desc) as rnk
    from public.community_files
    group by owner_id
  )
  select json_build_object(
    'rank', (select rnk from ranked where owner_id = p_user_id),
    'total_downloads', (select total_downloads from ranked where owner_id = p_user_id),
    'total_users', (select count(*) from ranked)
  );
$$;
grant execute on function public.get_user_rank(uuid) to anon, authenticated;

-- قائمة أفضل 50 (Leaderboard) عام للجميع
create or replace function public.get_leaderboard(p_limit int default 50)
returns json language sql stable as $$
  select coalesce(json_agg(t), '[]'::json) from (
    select p.id as user_id, p.username, p.display_name, p.public_id,
           coalesce(sum(cf.download_count), 0) as total_downloads,
           count(cf.id) as file_count
    from public.profiles p
    join public.community_files cf on cf.owner_id = p.id
    group by p.id, p.username, p.display_name, p.public_id
    order by total_downloads desc
    limit p_limit
  ) t;
$$;
grant execute on function public.get_leaderboard(int) to anon, authenticated;

-- ============================================================
-- مكتبتي — رسائل خاصة بين المستخدمين (زي واتساب خفيف)
-- شغّله بعد profiles-and-badges.sql
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) المحادثات والرسائل
-- ------------------------------------------------------------
drop table if exists public.dm_messages cascade;
drop table if exists public.dm_conversations cascade;

create table public.dm_conversations (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_a, user_b),
  check (user_a < user_b) -- ترتيب ثابت عشان مايتعملش صفين لنفس الاتنين
);
alter table public.dm_conversations enable row level security;
create policy "dm_conversations_participant_select"
  on public.dm_conversations for select
  using (auth.uid() = user_a or auth.uid() = user_b);
create policy "dm_conversations_participant_insert"
  on public.dm_conversations for insert
  with check (auth.uid() = user_a or auth.uid() = user_b);

-- ------------------------------------------------------------
-- 2) الحظر (Block) بين مستخدمين — لازم يتعمل قبل جدول الرسائل، لأن
-- صلاحية إرسال الرسائل تحت بتتأكد من الحظر ده
-- ------------------------------------------------------------
drop table if exists public.dm_blocks cascade;
create table public.dm_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
alter table public.dm_blocks enable row level security;
create policy "dm_blocks_owner_all"
  on public.dm_blocks for all
  using (auth.uid() = blocker_id)
  with check (auth.uid() = blocker_id);
-- تقدر تشوف هل انت محظور عند حد؟ لأ (خصوصية) — بس تقدر تشوف قائمتك انت
create policy "dm_blocks_check_if_blocked"
  on public.dm_blocks for select
  using (auth.uid() = blocker_id or auth.uid() = blocked_id);

create table public.dm_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.dm_messages enable row level security;
create policy "dm_messages_participant_select"
  on public.dm_messages for select
  using (exists (
    select 1 from public.dm_conversations c
    where c.id = conversation_id and (c.user_a = auth.uid() or c.user_b = auth.uid())
  ));
create policy "dm_messages_participant_insert"
  on public.dm_messages for insert
  with check (
    sender_id = auth.uid()
    and exists (select 1 from public.dm_conversations c where c.id = conversation_id and (c.user_a = auth.uid() or c.user_b = auth.uid()))
    -- ممنوع تبعت لحد حاظرك أو انت حاظره
    and not exists (
      select 1 from public.dm_blocks b
      join public.dm_conversations c2 on c2.id = conversation_id
      where (b.blocker_id = auth.uid() and b.blocked_id in (c2.user_a, c2.user_b) and b.blocked_id <> auth.uid())
         or (b.blocked_id = auth.uid() and b.blocker_id in (c2.user_a, c2.user_b) and b.blocker_id <> auth.uid())
    )
  );
create policy "dm_messages_participant_update_read"
  on public.dm_messages for update
  using (exists (
    select 1 from public.dm_conversations c
    where c.id = conversation_id and (c.user_a = auth.uid() or c.user_b = auth.uid())
  ));

-- ------------------------------------------------------------
-- 3) بلاغات على محادثة
-- ------------------------------------------------------------
drop table if exists public.dm_reports cascade;
create table public.dm_reports (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.dm_conversations(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  reason text,
  status text not null default 'pending' check (status in ('pending', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);
alter table public.dm_reports enable row level security;
create policy "dm_reports_insert_participant"
  on public.dm_reports for insert
  with check (
    reporter_id = auth.uid()
    and exists (select 1 from public.dm_conversations c where c.id = conversation_id and (c.user_a = auth.uid() or c.user_b = auth.uid()))
  );
create policy "dm_reports_admin_all"
  on public.dm_reports for all
  using (public.is_admin())
  with check (public.is_admin());

-- ------------------------------------------------------------
-- 4) الحظر النهائي من المنصة (الأدمن) — عمود على profile_private
-- ------------------------------------------------------------
alter table public.profile_private add column if not exists banned boolean not null default false;
alter table public.profile_private add column if not exists ban_reason text;

-- ------------------------------------------------------------
-- 5) حد أقصى للرسائل يتجدد كل فترة (زي ليمت الذكاء الاصطناعي بالظبط)
-- 30 رسالة كل 6 ساعات لكل مستخدم — عدّل الرقمين هنا لو حبيت تغيّرهم
-- ------------------------------------------------------------
create or replace function public.dm_check_rate_limit()
returns json language plpgsql security definer set search_path = public as $$
declare
  v_limit int := 30;
  v_window interval := interval '6 hours';
  v_used int;
  v_banned boolean;
begin
  select banned into v_banned from public.profile_private where id = auth.uid();
  if v_banned then
    return json_build_object('allowed', false, 'reason', 'banned');
  end if;

  select count(*) into v_used
    from public.dm_messages
    where sender_id = auth.uid() and created_at > now() - v_window;

  return json_build_object(
    'allowed', v_used < v_limit,
    'used', v_used,
    'limit', v_limit,
    'resets_in_seconds', extract(epoch from (
      (select min(created_at) from public.dm_messages where sender_id = auth.uid() and created_at > now() - v_window) + v_window - now()
    ))
  );
end;
$$;
grant execute on function public.dm_check_rate_limit() to authenticated;

-- ------------------------------------------------------------
-- 6) دالة تبدأ (أو تجيب) محادثة بين المستخدم الحالي وحد تاني بالـID
-- العام بتاعه — الواجهة بتنده على الدالة دي بدل ما تتعامل مع الجدول
-- مباشرة (بتتأكد كمان إن مفيش حظر متبادل)
-- ------------------------------------------------------------
create or replace function public.start_dm_conversation(p_public_id text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_other_id uuid;
  v_a uuid; v_b uuid;
  v_conv_id uuid;
begin
  select id into v_other_id from public.profiles where public_id = upper(p_public_id);
  if v_other_id is null then
    return json_build_object('error', 'مفيش حد بالمعرف ده');
  end if;
  if v_other_id = auth.uid() then
    return json_build_object('error', 'ده انت بنفسك 🙂');
  end if;
  if exists (select 1 from public.dm_blocks where blocker_id = auth.uid() and blocked_id = v_other_id) then
    return json_build_object('error', 'انت حاظر الشخص ده');
  end if;
  if exists (select 1 from public.dm_blocks where blocker_id = v_other_id and blocked_id = auth.uid()) then
    return json_build_object('error', 'مش ممكن تبدأ محادثة مع الشخص ده');
  end if;

  v_a := least(auth.uid(), v_other_id);
  v_b := greatest(auth.uid(), v_other_id);

  select id into v_conv_id from public.dm_conversations where user_a = v_a and user_b = v_b;
  if v_conv_id is null then
    insert into public.dm_conversations (user_a, user_b) values (v_a, v_b) returning id into v_conv_id;
  end if;
  return json_build_object('conversation_id', v_conv_id, 'other_user_id', v_other_id);
end;
$$;
grant execute on function public.start_dm_conversation(text) to authenticated;

-- ============================================================
-- مكتبتي — شارات إضافية + توحيد الإشعارات (رسائل خاصة كمان في نفس
-- الجرس) + عداد متابِعين/متابَعين للبروفايل
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) نسخة موسّعة من دالة الشارات — بتضيف: معلّق نشيط، عضو قديم،
-- مستكشف (حفظ مفضلة كتير)، اجتماعي (بيتابع كتير)، محبوب (ملفاته
-- اتحطت في مفضلة ناس كتير)، ومتابَع بقوة (50 متابع)
-- ------------------------------------------------------------
create or replace function public.check_and_award_badges(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_files_count int;
  v_downloads_total bigint;
  v_featured_count int;
  v_followers_count int;
  v_comments_count int;
  v_account_age interval;
  v_favorited_by_others_count int;
  v_following_count int;
  v_favorites_given_count int;
begin
  select count(*), coalesce(sum(download_count), 0)
    into v_files_count, v_downloads_total
    from public.community_files where owner_id = p_user_id;

  select count(*) into v_featured_count
    from public.community_files where owner_id = p_user_id and featured = true;

  select count(*) into v_followers_count
    from public.community_follows where follow_type = 'owner' and follow_value = p_user_id::text;

  select count(*) into v_comments_count
    from public.card_comments where user_id = p_user_id;

  select now() - created_at into v_account_age from public.profiles where id = p_user_id;

  select count(*) into v_favorited_by_others_count
    from public.community_saved s
    join public.community_files cf on cf.id = s.file_id
    where cf.owner_id = p_user_id and s.save_type = 'favorite';

  select count(*) into v_following_count
    from public.community_follows where user_id = p_user_id;

  select count(*) into v_favorites_given_count
    from public.community_saved where user_id = p_user_id and save_type = 'favorite';

  if v_files_count >= 1 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'first_publish') on conflict do nothing; end if;
  if v_downloads_total >= 10 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'ten_downloads') on conflict do nothing; end if;
  if v_downloads_total >= 100 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'hundred_downloads') on conflict do nothing; end if;
  if v_downloads_total >= 1000 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'thousand_downloads') on conflict do nothing; end if;
  if v_featured_count >= 1 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'featured_creator') on conflict do nothing; end if;
  if v_followers_count >= 10 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'popular_creator') on conflict do nothing; end if;
  if v_followers_count >= 50 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'super_followed') on conflict do nothing; end if;
  if v_files_count >= 10 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'ten_files') on conflict do nothing; end if;
  if v_comments_count >= 5 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'commentator') on conflict do nothing; end if;
  if v_account_age >= interval '90 days' then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'veteran') on conflict do nothing; end if;
  if v_favorited_by_others_count >= 20 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'beloved') on conflict do nothing; end if;
  if v_following_count >= 5 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'social') on conflict do nothing; end if;
  if v_favorites_given_count >= 10 then insert into public.user_badges (user_id, badge_key) values (p_user_id, 'explorer') on conflict do nothing; end if;
end;
$$;

-- تشغيل فحص الشارات كمان لما حد يعلّق، يحفظ مفضلة، أو يتابع حاجة
create or replace function public.trg_check_badges_generic(p_user_id uuid)
returns void language sql as $$ select public.check_and_award_badges(p_user_id); $$;

create or replace function public.trg_badges_on_comment()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.check_and_award_badges(new.user_id);
  return new;
end;
$$;
drop trigger if exists trg_badges_comment on public.card_comments;
create trigger trg_badges_comment
  after insert on public.card_comments
  for each row execute function public.trg_badges_on_comment();

create or replace function public.trg_badges_on_save()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  -- بتفحص شارات الشخص اللي حفظ (مستكشف) وصاحب الملف اللي اتحفظ (محبوب)
  perform public.check_and_award_badges(new.user_id);
  perform public.check_and_award_badges(cf.owner_id) from public.community_files cf where cf.id = new.file_id;
  return new;
end;
$$;
drop trigger if exists trg_badges_save on public.community_saved;
create trigger trg_badges_save
  after insert on public.community_saved
  for each row execute function public.trg_badges_on_save();

-- ------------------------------------------------------------
-- 2) توحيد الإشعارات — رسالة خاصة جديدة كمان تظهر في نفس جرس
-- الإشعارات (مش بس عداد الرسائل لوحده)
-- ------------------------------------------------------------
create or replace function public.notify_on_new_dm()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_conv record;
  v_recipient uuid;
  v_sender_name text;
begin
  select * into v_conv from public.dm_conversations where id = new.conversation_id;
  v_recipient := case when v_conv.user_a = new.sender_id then v_conv.user_b else v_conv.user_a end;
  select coalesce(display_name, username) into v_sender_name from public.profiles where id = new.sender_id;
  insert into public.user_notifications (user_id, message, link_url)
  values (v_recipient, 'رسالة جديدة من ' || coalesce(v_sender_name, 'مستخدم'), '?dm=1');
  return new;
end;
$$;
drop trigger if exists trg_notify_on_dm on public.dm_messages;
create trigger trg_notify_on_dm
  after insert on public.dm_messages
  for each row execute function public.notify_on_new_dm();

-- ------------------------------------------------------------
-- 3) عدد المتابِعين وعدد اللي بتتابعهم — للبروفايل
-- ------------------------------------------------------------
create or replace function public.get_follow_counts(p_user_id uuid)
returns json language sql stable as $$
  select json_build_object(
    'followers', (select count(*) from public.community_follows where follow_type = 'owner' and follow_value = p_user_id::text),
    'following', (select count(*) from public.community_follows where user_id = p_user_id)
  );
$$;
grant execute on function public.get_follow_counts(uuid) to anon, authenticated;

-- ============================================================
-- مكتبتي — طلبات المحتوى + المسابقات/التحديات الدورية
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) طلبات المحتوى — مستخدم يطلب "محتاج ملخص كذا"، وأي حد يرد
-- برسالة أو برابط ملف من ملفاته المنشورة، وصاحب الطلب يختار الحل
-- ------------------------------------------------------------
drop table if exists public.content_request_replies cascade;
drop table if exists public.content_requests cascade;

create table public.content_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  status text not null default 'open' check (status in ('open', 'fulfilled', 'closed')),
  fulfilled_reply_id uuid,
  created_at timestamptz not null default now()
);
alter table public.content_requests enable row level security;
create policy "content_requests_public_read" on public.content_requests for select using (true);
create policy "content_requests_insert_own" on public.content_requests for insert with check (requester_id = auth.uid());
create policy "content_requests_update_own_or_admin" on public.content_requests for update
  using (requester_id = auth.uid() or public.is_admin())
  with check (requester_id = auth.uid() or public.is_admin());
create policy "content_requests_delete_own_or_admin" on public.content_requests for delete
  using (requester_id = auth.uid() or public.is_admin());

create table public.content_request_replies (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.content_requests(id) on delete cascade,
  responder_id uuid not null references auth.users(id) on delete cascade,
  file_id uuid references public.community_files(id) on delete set null,
  message text,
  created_at timestamptz not null default now()
);
alter table public.content_request_replies enable row level security;
create policy "content_request_replies_public_read" on public.content_request_replies for select using (true);
create policy "content_request_replies_insert_own" on public.content_request_replies for insert with check (responder_id = auth.uid());
create policy "content_request_replies_delete_own_or_admin" on public.content_request_replies for delete
  using (responder_id = auth.uid() or public.is_admin());

alter table public.content_requests
  add constraint content_requests_fulfilled_reply_fk foreign key (fulfilled_reply_id) references public.content_request_replies(id) on delete set null;

-- إشعار لصاحب البلاغ الأصلي لما يوصله رد جديد
create or replace function public.notify_on_request_reply()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_requester uuid;
  v_title text;
  v_responder_name text;
begin
  select requester_id, title into v_requester, v_title from public.content_requests where id = new.request_id;
  if v_requester = new.responder_id then return new; end if; -- مايبعتش إشعار لنفسه لو رد على طلبه هو بالغلط
  select coalesce(display_name, username) into v_responder_name from public.profiles where id = new.responder_id;
  insert into public.user_notifications (user_id, message, link_url)
  values (v_requester, coalesce(v_responder_name, 'مستخدم') || ' ردّ على طلبك: ' || v_title, '?requests=1');
  return new;
end;
$$;
drop trigger if exists trg_notify_request_reply on public.content_request_replies;
create trigger trg_notify_request_reply
  after insert on public.content_request_replies
  for each row execute function public.notify_on_request_reply();

-- ------------------------------------------------------------
-- 2) مسابقات/تحديات دورية — الأدمن بس يقدر يعمل مسابقة، أي مستخدم
-- يشارك بملف من ملفاته المنشورة أو ملاحظة نصية، والأدمن يختار الفايز
-- ------------------------------------------------------------
drop table if exists public.contest_entries cascade;
drop table if exists public.contests cascade;

create table public.contests (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  prize_description text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active', 'ended')),
  winner_user_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
alter table public.contests enable row level security;
create policy "contests_public_read" on public.contests for select using (true);
create policy "contests_admin_write" on public.contests for all
  using (public.is_admin())
  with check (public.is_admin());

create table public.contest_entries (
  id uuid primary key default gen_random_uuid(),
  contest_id uuid not null references public.contests(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  file_id uuid references public.community_files(id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  unique (contest_id, user_id)
);
alter table public.contest_entries enable row level security;
create policy "contest_entries_public_read" on public.contest_entries for select using (true);
create policy "contest_entries_insert_own" on public.contest_entries for insert with check (user_id = auth.uid());
create policy "contest_entries_delete_own_or_admin" on public.contest_entries for delete
  using (user_id = auth.uid() or public.is_admin());

-- شارة "بطل تحدي" أوتوماتيك لما الأدمن يختار فايز + إشعار للفايز
create or replace function public.on_contest_winner_picked()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.winner_user_id is not null and (old.winner_user_id is null or old.winner_user_id <> new.winner_user_id) then
    insert into public.user_badges (user_id, badge_key) values (new.winner_user_id, 'contest_winner') on conflict do nothing;
    insert into public.user_notifications (user_id, message, link_url)
    values (new.winner_user_id, '🏆 مبروك! انت الفايز في تحدي "' || new.title || '"', '?contests=1');
  end if;
  return new;
end;
$$;
drop trigger if exists trg_contest_winner on public.contests;
create trigger trg_contest_winner
  after update of winner_user_id on public.contests
  for each row execute function public.on_contest_winner_picked();

-- ============================================================
-- مكتبتي — المنتديات والمجموعات + نظام الأصدقاء
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) المنتديات/المجموعات — 4 منتديات عامة ثابتة (برمجة، عربي،
-- إنجليزي، تاريخ) يقدر أي حد يكتب فيها من غير عضوية، بالإضافة لأي
-- جروبات يعملها المستخدمين (عامة تنضم لها بضغطة، أو خاصة تحتاج دعوة)
-- ------------------------------------------------------------
drop table if exists public.forum_invites cascade;
drop table if exists public.forum_replies cascade;
drop table if exists public.forum_threads cascade;
drop table if exists public.forum_members cascade;
drop table if exists public.forums cascade;

create table public.forums (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  kind text not null default 'forum' check (kind in ('forum', 'group')),
  is_public boolean not null default true, -- عام (أي حد يشارك/ينضم) ولا خاص (يحتاج دعوة)
  is_default boolean not null default false, -- المنتديات الأربعة الأساسية، ماتتمسحش
  owner_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.forums enable row level security;
create policy "forums_public_read" on public.forums for select using (true);
create policy "forums_insert_own" on public.forums for insert with check (owner_id = auth.uid() and kind = 'group');
create policy "forums_update_owner_or_admin" on public.forums for update
  using (owner_id = auth.uid() or public.is_admin())
  with check (owner_id = auth.uid() or public.is_admin());
create policy "forums_delete_owner_or_admin" on public.forums for delete
  using ((owner_id = auth.uid() and not is_default) or public.is_admin());

insert into public.forums (name, description, kind, is_public, is_default) values
  ('برمجة', 'كل حاجة عن الكود، اللغات، والمشاريع', 'forum', true, true),
  ('عربي', 'نقاش وأسئلة في اللغة العربية وآدابها', 'forum', true, true),
  ('إنجليزي', 'تعلّم وتمرين اللغة الإنجليزية', 'forum', true, true),
  ('تاريخ', 'نقاشات وأسئلة تاريخية', 'forum', true, true)
on conflict do nothing;

-- دعوات الجروبات الخاصة — لازم تتعمل قبل جدول العضوية تحت، لأن
-- صلاحية الانضمام للعضوية بتتأكد من وجود دعوة مقبولة
create table public.forum_invites (
  id uuid primary key default gen_random_uuid(),
  forum_id uuid not null references public.forums(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invited_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  unique (forum_id, invited_user_id)
);
alter table public.forum_invites enable row level security;
create policy "forum_invites_involved_read" on public.forum_invites for select
  using (inviter_id = auth.uid() or invited_user_id = auth.uid());
create policy "forum_invites_insert_owner" on public.forum_invites for insert
  with check (inviter_id = auth.uid() and exists (select 1 from public.forums f where f.id = forum_id and f.owner_id = auth.uid()));
create policy "forum_invites_update_invited" on public.forum_invites for update
  using (invited_user_id = auth.uid())
  with check (invited_user_id = auth.uid());

-- عضوية الجروبات (مش المنتديات العامة الأربعة — دي مفتوحة للكل أصلاً)
create table public.forum_members (
  forum_id uuid not null references public.forums(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (forum_id, user_id)
);
alter table public.forum_members enable row level security;
create policy "forum_members_public_read" on public.forum_members for select using (true);
create policy "forum_members_insert_self_if_public_or_invited" on public.forum_members for insert
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.forums f where f.id = forum_id and (
        f.is_public = true
        or exists (select 1 from public.forum_invites i where i.forum_id = forum_id and i.invited_user_id = auth.uid() and i.status = 'accepted')
      )
    )
  );
create policy "forum_members_delete_self_or_owner" on public.forum_members for delete
  using (user_id = auth.uid() or exists (select 1 from public.forums f where f.id = forum_id and f.owner_id = auth.uid()) or public.is_admin());

-- ------------------------------------------------------------
-- 2) المواضيع والردود
-- ------------------------------------------------------------
create table public.forum_threads (
  id uuid primary key default gen_random_uuid(),
  forum_id uuid not null references public.forums(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text,
  pinned boolean not null default false,
  best_reply_id uuid,
  created_at timestamptz not null default now()
);
alter table public.forum_threads enable row level security;
create policy "forum_threads_public_read" on public.forum_threads for select using (true);
create policy "forum_threads_insert_member_or_public" on public.forum_threads for insert
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.forums f where f.id = forum_id and (
        f.is_public = true or exists (select 1 from public.forum_members m where m.forum_id = forum_id and m.user_id = auth.uid())
      )
    )
  );
create policy "forum_threads_update_own_or_owner_or_admin" on public.forum_threads for update
  using (user_id = auth.uid() or exists (select 1 from public.forums f where f.id = forum_id and f.owner_id = auth.uid()) or public.is_admin())
  with check (user_id = auth.uid() or exists (select 1 from public.forums f where f.id = forum_id and f.owner_id = auth.uid()) or public.is_admin());
create policy "forum_threads_delete_own_or_owner_or_admin" on public.forum_threads for delete
  using (user_id = auth.uid() or exists (select 1 from public.forums f where f.id = forum_id and f.owner_id = auth.uid()) or public.is_admin());

create table public.forum_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.forum_threads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  likes_count int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.forum_replies enable row level security;
create policy "forum_replies_public_read" on public.forum_replies for select using (true);
create policy "forum_replies_insert_member_or_public" on public.forum_replies for insert
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.forum_threads t join public.forums f on f.id = t.forum_id
      where t.id = thread_id and (f.is_public = true or exists (select 1 from public.forum_members m where m.forum_id = f.id and m.user_id = auth.uid()))
    )
  );
create policy "forum_replies_delete_own_or_admin" on public.forum_replies for delete
  using (user_id = auth.uid() or public.is_admin());

alter table public.forum_threads
  add constraint forum_threads_best_reply_fk foreign key (best_reply_id) references public.forum_replies(id) on delete set null;

-- إعجاب على رد (بدون جدول منفصل — نكتفي بعداد بسيط بيتزوّد عن طريق دالة،
-- عشان ما نعقدش الموضوع بجدول تتبّع مين عمل لايك. لو حبيت منع تكرار
-- اللايك من نفس الشخص، قولّي نضيف جدول forum_reply_likes منفصل)
create or replace function public.increment_reply_likes(p_reply_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.forum_replies set likes_count = likes_count + 1 where id = p_reply_id;
$$;
grant execute on function public.increment_reply_likes(uuid) to authenticated;

-- إشعار لصاحب الموضوع لما يوصله رد جديد
create or replace function public.notify_on_forum_reply()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_thread record;
  v_responder_name text;
begin
  select * into v_thread from public.forum_threads where id = new.thread_id;
  if v_thread.user_id = new.user_id then return new; end if;
  select coalesce(display_name, username) into v_responder_name from public.profiles where id = new.user_id;
  insert into public.user_notifications (user_id, message, link_url)
  values (v_thread.user_id, coalesce(v_responder_name, 'مستخدم') || ' ردّ على موضوعك: ' || v_thread.title, '?forums=1');
  return new;
end;
$$;
drop trigger if exists trg_notify_forum_reply on public.forum_replies;
create trigger trg_notify_forum_reply
  after insert on public.forum_replies
  for each row execute function public.notify_on_forum_reply();

-- ------------------------------------------------------------
-- 3) دعوات الجروبات الخاصة — الجدول والصلاحيات اتعملوا فوق قبل
-- forum_members (كانوا محتاجين يتعملوا الأول عشانها)؛ هنا بس الـ
-- triggers المرتبطة بيها
-- ------------------------------------------------------------
create or replace function public.notify_on_forum_invite()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_forum_name text;
begin
  select name into v_forum_name from public.forums where id = new.forum_id;
  insert into public.user_notifications (user_id, message, link_url)
  values (new.invited_user_id, 'دعوة للانضمام لجروب "' || v_forum_name || '"', '?forums=1');
  return new;
end;
$$;
drop trigger if exists trg_notify_forum_invite on public.forum_invites;
create trigger trg_notify_forum_invite
  after insert on public.forum_invites
  for each row execute function public.notify_on_forum_invite();

-- لما الدعوة تتقبل، ينضاف المستخدم للجروب أوتوماتيك
create or replace function public.on_forum_invite_accepted()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'accepted' and old.status <> 'accepted' then
    insert into public.forum_members (forum_id, user_id) values (new.forum_id, new.invited_user_id) on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_forum_invite_accepted on public.forum_invites;
create trigger trg_forum_invite_accepted
  after update of status on public.forum_invites
  for each row execute function public.on_forum_invite_accepted();

-- ------------------------------------------------------------
-- 4) الأصدقاء — طلب صداقة بمعرّف عام، وبمجرد القبول يترابطوا
-- ------------------------------------------------------------
drop table if exists public.friendships cascade;
create table public.friendships (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
alter table public.friendships enable row level security;
create policy "friendships_involved_read" on public.friendships for select
  using (auth.uid() = user_a or auth.uid() = user_b);
create policy "friendships_involved_update" on public.friendships for update
  using (auth.uid() = user_a or auth.uid() = user_b)
  with check (auth.uid() = user_a or auth.uid() = user_b);
create policy "friendships_involved_delete" on public.friendships for delete
  using (auth.uid() = user_a or auth.uid() = user_b);
-- الإدراج بس عن طريق الدالة تحت (مش مباشر) عشان نضمن ترتيب user_a<user_b صح

create or replace function public.send_friend_request(p_public_id text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_other_id uuid;
  v_a uuid; v_b uuid;
  v_existing record;
begin
  select id into v_other_id from public.profiles where public_id = upper(p_public_id);
  if v_other_id is null then return json_build_object('error', 'مفيش حد بالمعرف ده'); end if;
  if v_other_id = auth.uid() then return json_build_object('error', 'ده انت بنفسك 🙂'); end if;

  v_a := least(auth.uid(), v_other_id);
  v_b := greatest(auth.uid(), v_other_id);
  select * into v_existing from public.friendships where user_a = v_a and user_b = v_b;

  if v_existing.status = 'accepted' then return json_build_object('error', 'انتوا أصدقاء بالفعل'); end if;
  if v_existing.status = 'pending' and v_existing.requested_by = auth.uid() then return json_build_object('error', 'الطلب مبعوت بالفعل، مستني رد'); end if;
  if v_existing.status = 'pending' and v_existing.requested_by <> auth.uid() then
    update public.friendships set status = 'accepted' where user_a = v_a and user_b = v_b;
    insert into public.user_notifications (user_id, message, link_url)
      select v_existing.requested_by, coalesce(p.display_name, p.username) || ' قبل طلب صداقتك', '?friends=1' from public.profiles p where p.id = auth.uid();
    return json_build_object('ok', true, 'status', 'accepted');
  end if;

  insert into public.friendships (user_a, user_b, requested_by) values (v_a, v_b, auth.uid());
  insert into public.user_notifications (user_id, message, link_url)
    select v_other_id, coalesce(p.display_name, p.username) || ' بيبعتلك طلب صداقة', '?friends=1' from public.profiles p where p.id = auth.uid();
  return json_build_object('ok', true, 'status', 'pending');
end;
$$;
grant execute on function public.send_friend_request(text) to authenticated;

-- ------------------------------------------------------------
-- 5) شارة "نشيط في المنتديات"
-- ------------------------------------------------------------
create or replace function public.trg_badges_on_forum_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_count int;
begin
  select count(*) into v_count from public.forum_threads where user_id = new.user_id;
  select v_count + count(*) into v_count from public.forum_replies where user_id = new.user_id;
  if v_count >= 10 then
    insert into public.user_badges (user_id, badge_key) values (new.user_id, 'forum_active') on conflict do nothing;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_badges_thread on public.forum_threads;
create trigger trg_badges_thread after insert on public.forum_threads for each row execute function public.trg_badges_on_forum_activity();
drop trigger if exists trg_badges_reply on public.forum_replies;
create trigger trg_badges_reply after insert on public.forum_replies for each row execute function public.trg_badges_on_forum_activity();

-- ============================================================
-- مكتبتي — نظام بلاغات موحّد (بروفايلات، منتديات/جروبات، مواضيع)
-- + تحسينات إضافية لعدة أقسام
-- شغّله بعد كل ملفات SQL اللي قبله
-- Supabase Dashboard > SQL Editor > New query > Run
-- ============================================================

-- ------------------------------------------------------------
-- 1) بلاغات موحّدة — جدول واحد لأي نوع هدف (بروفايل/منتدى أو
-- جروب/موضوع)، بدل جدول منفصل لكل نوع. بلاغات الرسائل الخاصة
-- فضلّت في جدولها القديم (dm_reports) عشان ميتلمسش شيء شغال فعلاً
-- ------------------------------------------------------------
drop table if exists public.content_reports cascade;
create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('profile', 'forum', 'thread')),
  target_id uuid not null,
  target_label text, -- اسم/عنوان الهدف وقت الإبلاغ (لو اتمسح بعدين نفضل عارفين كان إيه)
  reason text,
  status text not null default 'pending' check (status in ('pending', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);
alter table public.content_reports enable row level security;
create policy "content_reports_insert_own" on public.content_reports for insert with check (reporter_id = auth.uid());
create policy "content_reports_admin_all" on public.content_reports for all
  using (public.is_admin())
  with check (public.is_admin());

-- ------------------------------------------------------------
-- 2) عشان مؤشر "متصل الآن" في قائمة الأصدقاء يشتغل فعليًا — بدون
-- الـpolicy دي، profile_private مقفولة على صاحبها بس، فمؤشر "متصل
-- الآن" كان هيفضل مايظهرش خالص لأي حد غيرك. هنا بس الأصدقاء المتقابل
-- عليهم (accepted) يقدروا يشوفوا last_seen_at بتاعت بعض، مش أي حد
-- ------------------------------------------------------------
create policy "profile_private_friends_read"
  on public.profile_private for select
  using (
    exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.user_a = auth.uid() and f.user_b = profile_private.id) or (f.user_b = auth.uid() and f.user_a = profile_private.id))
    )
  );

-- ------------------------------------------------------------
-- 3) تحسينات إضافية:
-- أ) عدد أعضاء كل جروب (للعرض في قائمة المنتديات/المجموعات)
-- ب) عدد ردود كل موضوع (لترتيب "الأكثر نقاشًا")
-- ج) "متصل الآن" ضمن قائمة الأصدقاء (نستخدم last_seen_at الموجود بالفعل)
-- ------------------------------------------------------------
create or replace function public.get_forum_member_counts()
returns json language sql stable as $$
  select coalesce(json_object_agg(forum_id, cnt), '{}'::json)
  from (select forum_id, count(*) as cnt from public.forum_members group by forum_id) t;
$$;
grant execute on function public.get_forum_member_counts() to anon, authenticated;

create or replace function public.get_thread_reply_counts(p_forum_id uuid)
returns json language sql stable as $$
  select coalesce(json_object_agg(thread_id, cnt), '{}'::json)
  from (
    select t.id as thread_id, count(r.id) as cnt
    from public.forum_threads t
    left join public.forum_replies r on r.thread_id = t.id
    where t.forum_id = p_forum_id
    group by t.id
  ) x;
$$;
grant execute on function public.get_thread_reply_counts(uuid) to anon, authenticated;

-- ############################################################
-- تقوية الأمان (Hardening) — تمنع التحايل المباشر على الـAPI
-- كل اللي تحت بيتنفّذ في السيرفر نفسه، فمينفعش المتصفح يتخطّاه
-- ############################################################

-- 1) profiles: المستخدم يعدّل الاسم الظاهر بس — مش الـid ولا الـpublic_id ولا username
create or replace function public.guard_profiles_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.id := old.id;
    new.username := old.username;
    new.public_id := old.public_id;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
drop trigger if exists before_profiles_update_guard on public.profiles;
create trigger before_profiles_update_guard before update on public.profiles
  for each row execute procedure public.guard_profiles_update();

-- 2) profile_private: ممنوع المستخدم يفك الحظر/التعطيل عن نفسه
create or replace function public.protect_disabled_field()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.id := old.id;
    new.disabled := old.disabled;
    new.banned := old.banned;
    new.ban_reason := old.ban_reason;
  end if;
  return new;
end;
$$;

-- الأدمن لازم يقدر يعدّل صف أي مستخدم (حظر/تعطيل) — من غير الـpolicy دي
-- كان UPDATE بيرجّع 0 صفوف بصمت والحظر مابيحصلش فعليًا
drop policy if exists "profile_private_admin_update" on public.profile_private;
create policy "profile_private_admin_update" on public.profile_private for update
  using (public.is_admin()) with check (public.is_admin());

-- 3) الرسائل الخاصة: الحظر + الحد الأقصى (30 كل 6 ساعات) + الطول — في السيرفر
create or replace function public.dm_enforce_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_banned boolean; v_used int;
begin
  select banned into v_banned from public.profile_private where id = new.sender_id;
  if coalesce(v_banned, false) then
    raise exception 'حسابك محظور من المراسلة';
  end if;
  new.message := btrim(coalesce(new.message, ''));
  if length(new.message) = 0 or length(new.message) > 2000 then
    raise exception 'الرسالة فاضية أو أطول من 2000 حرف';
  end if;
  select count(*) into v_used from public.dm_messages
    where sender_id = new.sender_id and created_at > now() - interval '6 hours';
  if v_used >= 30 then
    raise exception 'وصلت للحد الأقصى للرسائل — حاول بعد شوية';
  end if;
  new.read := false;
  new.created_at := now();
  return new;
end;
$$;
drop trigger if exists before_dm_messages_insert on public.dm_messages;
create trigger before_dm_messages_insert before insert on public.dm_messages
  for each row execute procedure public.dm_enforce_insert();

-- الرسالة ما تتعدّلش: الوحيد المسموح هو "تمت القراءة" وبواسطة المستقبِل بس
create or replace function public.dm_guard_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.id := old.id; new.conversation_id := old.conversation_id; new.sender_id := old.sender_id;
  new.message := old.message; new.created_at := old.created_at;
  if old.sender_id = auth.uid() then new.read := old.read; end if;
  if old.read then new.read := true; end if;
  return new;
end;
$$;
drop trigger if exists before_dm_messages_update on public.dm_messages;
create trigger before_dm_messages_update before update on public.dm_messages
  for each row execute procedure public.dm_guard_update();

-- 4) الصداقة: اللي بعت الطلب مايقدرش يقبل طلبه بنفسه
create or replace function public.guard_friendship_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then return new; end if;
  new.user_a := old.user_a; new.user_b := old.user_b;
  new.requested_by := old.requested_by; new.created_at := old.created_at;
  if old.status = 'accepted' then new.status := 'accepted'; end if;
  if old.status = 'pending' and new.status = 'accepted' and auth.uid() = old.requested_by then
    new.status := 'pending';
  end if;
  return new;
end;
$$;
drop trigger if exists before_friendship_update on public.friendships;
create trigger before_friendship_update before update on public.friendships
  for each row execute procedure public.guard_friendship_update();

-- 5) المنتديات/المجموعات
create or replace function public.guard_forums_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.is_default := old.is_default; new.owner_id := old.owner_id;
    new.kind := old.kind; new.created_at := old.created_at;
  end if;
  return new;
end;
$$;
drop trigger if exists before_forums_update on public.forums;
create trigger before_forums_update before update on public.forums
  for each row execute procedure public.guard_forums_update();

create or replace function public.guard_threads_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_is_owner boolean;
begin
  new.id := old.id; new.forum_id := old.forum_id; new.user_id := old.user_id; new.created_at := old.created_at;
  select exists(select 1 from public.forums f where f.id = old.forum_id and f.owner_id = auth.uid()) into v_is_owner;
  if not (public.is_admin() or v_is_owner) then new.pinned := old.pinned; end if;
  if new.best_reply_id is not null and not exists (
    select 1 from public.forum_replies r where r.id = new.best_reply_id and r.thread_id = old.id
  ) then new.best_reply_id := old.best_reply_id; end if;
  return new;
end;
$$;
drop trigger if exists before_threads_update on public.forum_threads;
create trigger before_threads_update before update on public.forum_threads
  for each row execute procedure public.guard_threads_update();

-- المجموعات الخاصة: محتواها للأعضاء والأدمن بس (كان مفتوح للكل)
drop policy if exists "forum_threads_public_read" on public.forum_threads;
create policy "forum_threads_read_if_allowed" on public.forum_threads for select
  using (
    public.is_admin() or exists (
      select 1 from public.forums f where f.id = forum_id and (
        f.is_public = true
        or exists (select 1 from public.forum_members m where m.forum_id = f.id and m.user_id = auth.uid())
      )
    )
  );
drop policy if exists "forum_replies_public_read" on public.forum_replies;
create policy "forum_replies_read_if_allowed" on public.forum_replies for select
  using (
    public.is_admin() or exists (
      select 1 from public.forum_threads t join public.forums f on f.id = t.forum_id
      where t.id = thread_id and (
        f.is_public = true
        or exists (select 1 from public.forum_members m where m.forum_id = f.id and m.user_id = auth.uid())
      )
    )
  );

-- العضوية: دور "owner" لصاحب المجموعة بس
drop policy if exists "forum_members_insert_self_if_public_or_invited" on public.forum_members;
create policy "forum_members_insert_self_if_public_or_invited" on public.forum_members for insert
  with check (
    user_id = auth.uid() and exists (
      select 1 from public.forums f where f.id = forum_id and (
        (role = 'owner' and f.owner_id = auth.uid())
        or (role = 'member' and (
          f.is_public = true
          or exists (select 1 from public.forum_invites i where i.forum_id = forum_id and i.invited_user_id = auth.uid() and i.status = 'accepted')
        ))
      )
    )
  );

-- الردود: العداد يبدأ من صفر، واللايك مرة واحدة لكل مستخدم
create or replace function public.guard_reply_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.likes_count := 0;
  new.message := btrim(coalesce(new.message, ''));
  if length(new.message) = 0 or length(new.message) > 5000 then raise exception 'الرد فاضي أو طويل جدًا'; end if;
  return new;
end;
$$;
drop trigger if exists before_reply_insert on public.forum_replies;
create trigger before_reply_insert before insert on public.forum_replies
  for each row execute procedure public.guard_reply_insert();

drop table if exists public.forum_reply_likes cascade;
create table public.forum_reply_likes (
  reply_id uuid not null references public.forum_replies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (reply_id, user_id)
);
alter table public.forum_reply_likes enable row level security; -- من غير policies: الوصول عبر الدالة بس

create or replace function public.increment_reply_likes(p_reply_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.forum_reply_likes (reply_id, user_id) values (p_reply_id, auth.uid())
    on conflict do nothing;
  if found then
    update public.forum_replies set likes_count = likes_count + 1 where id = p_reply_id;
  end if;
end;
$$;
grant execute on function public.increment_reply_likes(uuid) to authenticated;

-- ------------------------------------------------------------
-- Realtime: من غير الجداول دي في publication الرسايل والإشعارات
-- ماكانتش بتوصل لحظيًا (الأمان بيفضل بيتحكم فيه RLS)
-- ------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['dm_messages','forum_replies','forum_threads','user_notifications','admin_chat_messages']
  loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
             when undefined_object then null;
             when undefined_table then null;
    end;
  end loop;
end $$;

-- ############################################################
-- من ملف: تشغيل رفع ملفات المستخدمين.sql
-- ############################################################
-- ============================================================
-- خطوة إضافية بعد أي تصفير (المسح الافتراضي فوق بيمسح public.* بس،
-- مش auth.users) — أي حساب كان موجود قبل التصفير هيفضل من غير صف في
-- profiles / profile_private، لأن الـtrigger بتاعهم بيشتغل بس وقت
-- إنشاء حساب جديد، مش بأثر رجعي. الكود ده بيرجّع الصفوف دي لكل
-- الحسابات القديمة اللي فاتها الـtrigger.
-- ============================================================
insert into public.profiles (id, username, display_name)
select id,
       coalesce(raw_user_meta_data->>'username', split_part(email,'@',1)),
       coalesce(raw_user_meta_data->>'display_name', split_part(email,'@',1))
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

insert into public.profile_private (id, gender, last_seen_at)
select id, raw_user_meta_data->>'gender', now()
from auth.users u
where not exists (select 1 from public.profile_private p where p.id = u.id);

-- ############################################################
-- من ملف: admin.sql
-- ############################################################
-- ============================================================
-- إعادة تعيين الأدمن بعد التصفير — جدول admins اتمسح زي أي جدول
-- تاني في القسم "ابدأ من جديد" فوق، فلازم يترجّع يدويًا هنا. لازم
-- يتنفذ بعد سطر الـinsert في profiles فوق (وبعد ما الحساب يكون
-- عامل تسجيل دخول مرة على الأقل عشان يبقى موجود في auth.users أصلاً).
-- ============================================================
insert into public.admins (user_id)
select id from auth.users
where raw_user_meta_data ->> 'username' = 'Ahmed5565';
