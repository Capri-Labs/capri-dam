SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


--
-- Name: protect_audit_logs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.protect_audit_logs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'Audit logs are immutable and cannot be updated or deleted.';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    record_id bigint NOT NULL,
    record_type character varying NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    content_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    filename character varying NOT NULL,
    key character varying NOT NULL,
    metadata text,
    service_name character varying NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: agent_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_executions (
    id bigint NOT NULL,
    agent_workflow_id bigint NOT NULL,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    duration_ms integer,
    error_message text,
    output jsonb DEFAULT '{}'::jsonb NOT NULL,
    started_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    summary text,
    trigger_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    trigger_type character varying DEFAULT 'event'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: agent_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_executions_id_seq OWNED BY public.agent_executions.id;


--
-- Name: agent_workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_workflows (
    id bigint NOT NULL,
    active boolean DEFAULT false NOT NULL,
    agent_model character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id bigint,
    description text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    name character varying NOT NULL,
    tools_enabled jsonb DEFAULT '[]'::jsonb NOT NULL,
    trigger_event character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: agent_workflows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agent_workflows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_workflows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agent_workflows_id_seq OWNED BY public.agent_workflows.id;


--
-- Name: ai_batch_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_batch_jobs (
    id bigint NOT NULL,
    completed_at timestamp(6) without time zone,
    concurrency integer DEFAULT 25 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id bigint,
    error_message text,
    failed_count integer DEFAULT 0 NOT NULL,
    options jsonb DEFAULT '{}'::jsonb NOT NULL,
    processed_count integer DEFAULT 0 NOT NULL,
    started_at timestamp(6) without time zone,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    succeeded_count integer DEFAULT 0 NOT NULL,
    target_scope character varying NOT NULL,
    task_type character varying NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_batch_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_batch_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_batch_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_batch_jobs_id_seq OWNED BY public.ai_batch_jobs.id;


--
-- Name: ai_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_configurations (
    id bigint NOT NULL,
    active_provider character varying,
    created_at timestamp(6) without time zone NOT NULL,
    current_spend_usd numeric,
    embedding_model character varying,
    fallback_to_local boolean,
    generation_model character varying,
    monthly_budget_usd numeric,
    system_prompt text,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_configurations_id_seq OWNED BY public.ai_configurations.id;


--
-- Name: ai_model_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_model_configs (
    id bigint NOT NULL,
    capability character varying DEFAULT 'generation'::character varying NOT NULL,
    config_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    error_message text,
    health_latency_ms integer,
    health_status character varying DEFAULT 'unknown'::character varying NOT NULL,
    is_default boolean DEFAULT false NOT NULL,
    last_health_check_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    model_id character varying NOT NULL,
    name character varying NOT NULL,
    provider character varying DEFAULT 'openai'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_model_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ai_model_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ai_model_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ai_model_configs_id_seq OWNED BY public.ai_model_configs.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_embeddings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_embeddings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    asset_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    embedding public.vector(1536) NOT NULL,
    model_name character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_provenance_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_provenance_records (
    id bigint NOT NULL,
    ai_tools_used jsonb DEFAULT '[]'::jsonb NOT NULL,
    asset_id uuid NOT NULL,
    claim_generator character varying,
    created_at timestamp(6) without time zone NOT NULL,
    error_detail text,
    is_ai_modified boolean DEFAULT false NOT NULL,
    manifest_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    manifest_status character varying DEFAULT 'unchecked'::character varying NOT NULL,
    signed_at timestamp(6) without time zone,
    signer_cert_fingerprint character varying,
    signer_name character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    verified_at timestamp(6) without time zone
);


--
-- Name: asset_provenance_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asset_provenance_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asset_provenance_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asset_provenance_records_id_seq OWNED BY public.asset_provenance_records.id;


--
-- Name: asset_usage_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_usage_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    asset_id uuid NOT NULL,
    user_id bigint NOT NULL,
    event_type character varying DEFAULT 'view'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: asset_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    action_type character varying DEFAULT 'initial_upload'::character varying,
    asset_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id bigint,
    properties jsonb DEFAULT '{}'::jsonb,
    updated_at timestamp(6) without time zone NOT NULL,
    version_number integer DEFAULT 1 NOT NULL
);


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    active_version_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    folder_id uuid,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying DEFAULT 'draft'::character varying,
    title character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    uuid character varying NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id bigint NOT NULL,
    action character varying,
    auditable_id integer,
    auditable_type character varying,
    changes_data jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    impersonated boolean DEFAULT false NOT NULL,
    ip_address character varying,
    true_user_id bigint,
    updated_at timestamp(6) without time zone NOT NULL,
    user_agent character varying,
    user_id bigint
);


--
-- Name: audit_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_logs_id_seq OWNED BY public.audit_logs.id;


--
-- Name: c2pa_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.c2pa_configurations (
    id bigint NOT NULL,
    ai_disclosure_required boolean DEFAULT true NOT NULL,
    auto_sign_on_ingest boolean DEFAULT false NOT NULL,
    auto_verify_on_ingest boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    gateway_c2pa_enabled boolean DEFAULT false NOT NULL,
    policy_notes text,
    require_c2pa_on_import boolean DEFAULT false NOT NULL,
    signing_issuer_name character varying,
    signing_org character varying,
    trust_store_urls jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    verification_strictness character varying DEFAULT 'lenient'::character varying NOT NULL
);


--
-- Name: c2pa_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.c2pa_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: c2pa_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.c2pa_configurations_id_seq OWNED BY public.c2pa_configurations.id;


--
-- Name: cdn_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cdn_configurations (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    is_active boolean,
    provider character varying,
    settings text,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cdn_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cdn_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cdn_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cdn_configurations_id_seq OWNED BY public.cdn_configurations.id;


--
-- Name: collection_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collection_assets (
    id bigint NOT NULL,
    asset_id uuid NOT NULL,
    collection_id bigint NOT NULL,
    collection_rule_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    pinned boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id integer
);


--
-- Name: collection_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.collection_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collection_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.collection_assets_id_seq OWNED BY public.collection_assets.id;


--
-- Name: collection_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collection_rules (
    id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    collection_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    metadata_filters jsonb DEFAULT '{}'::jsonb,
    semantic_prompt text NOT NULL,
    similarity_threshold numeric(4,3) DEFAULT 0.8,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: collection_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.collection_rules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collection_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.collection_rules_id_seq OWNED BY public.collection_rules.id;


--
-- Name: collections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collections (
    id bigint NOT NULL,
    collection_type character varying DEFAULT 'manual'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    description text,
    expires_at timestamp(6) without time zone,
    name character varying,
    properties jsonb,
    slug character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id integer,
    uuid uuid
);


--
-- Name: collections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.collections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: collections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.collections_id_seq OWNED BY public.collections.id;


--
-- Name: custom_node_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.custom_node_definitions (
    id bigint NOT NULL,
    key character varying NOT NULL,
    name character varying NOT NULL,
    description text,
    icon character varying,
    category character varying DEFAULT 'custom'::character varying NOT NULL,
    color character varying DEFAULT '#6366f1'::character varying NOT NULL,
    config_schema jsonb DEFAULT '[]'::jsonb NOT NULL,
    runtime jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    failure_count integer DEFAULT 0 NOT NULL,
    last_error text,
    last_dispatched_at timestamp(6) without time zone,
    created_by_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: custom_node_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.custom_node_definitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: custom_node_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.custom_node_definitions_id_seq OWNED BY public.custom_node_definitions.id;


--
-- Name: daily_metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.daily_metrics (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    metric_date date NOT NULL,
    metric_name character varying NOT NULL,
    metric_value integer DEFAULT 0,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: daily_metrics_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.daily_metrics_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: daily_metrics_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.daily_metrics_id_seq OWNED BY public.daily_metrics.id;


--
-- Name: duplicate_group_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.duplicate_group_assets (
    id bigint NOT NULL,
    asset_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    duplicate_group_id uuid NOT NULL,
    is_original boolean DEFAULT false NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: duplicate_group_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.duplicate_group_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: duplicate_group_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.duplicate_group_assets_id_seq OWNED BY public.duplicate_group_assets.id;


--
-- Name: duplicate_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.duplicate_groups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    checksum character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    resolution_action character varying,
    resolved_at timestamp(6) without time zone,
    resolved_by_id bigint,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: email_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_deliveries (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    email_template_id bigint NOT NULL,
    error_log text,
    payload text DEFAULT '{}'::text NOT NULL,
    recipient_email character varying NOT NULL,
    retry_count integer DEFAULT 0 NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: email_deliveries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.email_deliveries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_deliveries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.email_deliveries_id_seq OWNED BY public.email_deliveries.id;


--
-- Name: email_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_templates (
    id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    category character varying DEFAULT 'transactional'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id bigint,
    description text,
    event_trigger character varying NOT NULL,
    html_body text,
    name character varying NOT NULL,
    preview_data jsonb DEFAULT '{}'::jsonb NOT NULL,
    subject character varying NOT NULL,
    text_body text,
    updated_at timestamp(6) without time zone NOT NULL,
    variables jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: email_templates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.email_templates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: email_templates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.email_templates_id_seq OWNED BY public.email_templates.id;


--
-- Name: folder_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.folder_policies (
    id bigint NOT NULL,
    create_access boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    delete_access boolean DEFAULT false NOT NULL,
    explicit_deny boolean DEFAULT false NOT NULL,
    folder_id uuid NOT NULL,
    manage_access boolean DEFAULT false NOT NULL,
    modify_access boolean DEFAULT false NOT NULL,
    read_access boolean DEFAULT false NOT NULL,
    replicate_access boolean DEFAULT false NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_group_id bigint NOT NULL
);


--
-- Name: folder_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.folder_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: folder_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.folder_policies_id_seq OWNED BY public.folder_policies.id;


--
-- Name: folders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.folders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    description text,
    name character varying NOT NULL,
    parent_id uuid,
    path character varying,
    properties jsonb DEFAULT '{}'::jsonb,
    slug character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    uuid uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: image_profile_folder_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.image_profile_folder_assignments (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    folder_id uuid NOT NULL,
    image_profile_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: image_profile_folder_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.image_profile_folder_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: image_profile_folder_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.image_profile_folder_assignments_id_seq OWNED BY public.image_profile_folder_assignments.id;


--
-- Name: image_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.image_profiles (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    crop_type character varying DEFAULT 'none'::character varying NOT NULL,
    deleted_at timestamp(6) without time zone,
    name character varying NOT NULL,
    responsive_crop_enabled boolean DEFAULT false NOT NULL,
    responsive_crops jsonb DEFAULT '[]'::jsonb NOT NULL,
    swatch_enabled boolean DEFAULT false NOT NULL,
    swatch_height integer DEFAULT 100,
    swatch_width integer DEFAULT 100,
    unsharp_mask jsonb DEFAULT '{"amount": 1.75, "radius": 0.2, "threshold": 2}'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: image_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.image_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: image_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.image_profiles_id_seq OWNED BY public.image_profiles.id;


--
-- Name: in_app_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.in_app_notifications (
    id bigint NOT NULL,
    action_type character varying NOT NULL,
    actor_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    message character varying NOT NULL,
    notifiable_id bigint NOT NULL,
    notifiable_type character varying NOT NULL,
    read_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: in_app_notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.in_app_notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: in_app_notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.in_app_notifications_id_seq OWNED BY public.in_app_notifications.id;


--
-- Name: inbox_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbox_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    archived_at timestamp(6) without time zone,
    body_html text,
    body_text text,
    created_at timestamp(6) without time zone NOT NULL,
    email_template_id bigint,
    message_type character varying DEFAULT 'notification'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    read_at timestamp(6) without time zone,
    recipient_id bigint NOT NULL,
    reference_id uuid,
    reference_type character varying,
    sender_id bigint,
    starred_at timestamp(6) without time zone,
    subject character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ingestion_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingestion_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    committed_count integer DEFAULT 0,
    completed_at timestamp(6) without time zone,
    connector_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    destination_folder_id uuid,
    duplicate_count integer DEFAULT 0,
    error_count integer DEFAULT 0,
    initiated_by_id bigint,
    name character varying NOT NULL,
    notes text,
    processed_count integer DEFAULT 0,
    report_snapshot_id bigint,
    source_credentials jsonb DEFAULT '{}'::jsonb,
    source_type character varying NOT NULL,
    started_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    total_count integer DEFAULT 0,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id integer,
    source_path character varying,
    last_cursor character varying,
    migrate_metadata boolean DEFAULT true NOT NULL
);


--
-- Name: ingestion_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ingestion_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    clean_properties jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    error_log text,
    file_hash character varying,
    file_size bigint,
    ingestion_batch_id uuid NOT NULL,
    legacy_metadata jsonb DEFAULT '{}'::jsonb,
    original_filename character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    full_metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: metadata_exports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metadata_exports (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    error_message text,
    expires_at timestamp(6) without time zone,
    file_count integer DEFAULT 0 NOT NULL,
    folder_id uuid,
    include_subfolders boolean DEFAULT false NOT NULL,
    name character varying NOT NULL,
    property_mode character varying DEFAULT 'all'::character varying NOT NULL,
    scheduled_at timestamp(6) without time zone,
    selected_properties jsonb DEFAULT '[]'::jsonb NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    total_assets integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: metadata_exports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metadata_exports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metadata_exports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metadata_exports_id_seq OWNED BY public.metadata_exports.id;


--
-- Name: metadata_imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metadata_imports (
    id bigint NOT NULL,
    asset_path_column character varying DEFAULT 'asset_path'::character varying NOT NULL,
    batch_size integer DEFAULT 50 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    error_message text,
    expires_at timestamp(6) without time zone,
    failure_count integer DEFAULT 0 NOT NULL,
    field_separator character varying DEFAULT ','::character varying NOT NULL,
    ignored_columns jsonb DEFAULT '[]'::jsonb NOT NULL,
    launch_workflows boolean DEFAULT false NOT NULL,
    multi_value_delimiter character varying DEFAULT '|'::character varying NOT NULL,
    name character varying NOT NULL,
    scheduled_at timestamp(6) without time zone,
    status integer DEFAULT 0 NOT NULL,
    success_count integer DEFAULT 0 NOT NULL,
    total_rows integer DEFAULT 0 NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: metadata_imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metadata_imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metadata_imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metadata_imports_id_seq OWNED BY public.metadata_imports.id;


--
-- Name: metadata_schema_folder_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metadata_schema_folder_assignments (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    folder_id character varying NOT NULL,
    metadata_schema_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: metadata_schema_folder_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metadata_schema_folder_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metadata_schema_folder_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metadata_schema_folder_assignments_id_seq OWNED BY public.metadata_schema_folder_assignments.id;


--
-- Name: metadata_schemas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metadata_schemas (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    description text,
    is_builtin boolean DEFAULT false NOT NULL,
    level character varying DEFAULT 'root'::character varying NOT NULL,
    mime_segment character varying,
    name character varying NOT NULL,
    parent_id bigint,
    properties jsonb DEFAULT '{}'::jsonb NOT NULL,
    slug character varying NOT NULL,
    tabs jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    uuid character varying NOT NULL,
    inherits_from_id bigint
);


--
-- Name: metadata_schemas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.metadata_schemas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: metadata_schemas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.metadata_schemas_id_seq OWNED BY public.metadata_schemas.id;


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id bigint NOT NULL,
    action_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    message character varying,
    read_at timestamp(6) without time zone,
    title character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: notifications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.notifications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: notifications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.notifications_id_seq OWNED BY public.notifications.id;


--
-- Name: oauth_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_grants (
    id bigint NOT NULL,
    application_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    resource_owner_id bigint NOT NULL,
    revoked_at timestamp(6) without time zone,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    token character varying NOT NULL
);


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_grants_id_seq OWNED BY public.oauth_access_grants.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_access_tokens (
    id bigint NOT NULL,
    application_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    expires_in integer,
    previous_refresh_token character varying DEFAULT ''::character varying NOT NULL,
    refresh_token character varying,
    resource_owner_id bigint,
    revoked_at timestamp(6) without time zone,
    scopes character varying,
    token character varying NOT NULL
);


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_access_tokens_id_seq OWNED BY public.oauth_access_tokens.id;


--
-- Name: oauth_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oauth_applications (
    id bigint NOT NULL,
    confidential boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    owner_id integer,
    owner_type character varying,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    secret character varying NOT NULL,
    uid character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.oauth_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.oauth_applications_id_seq OWNED BY public.oauth_applications.id;


--
-- Name: personal_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.personal_access_tokens (
    id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone,
    last_four character varying NOT NULL,
    last_used_at timestamp(6) without time zone,
    name character varying NOT NULL,
    scopes character varying DEFAULT 'read'::character varying,
    token_digest character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: personal_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.personal_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: personal_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.personal_access_tokens_id_seq OWNED BY public.personal_access_tokens.id;


--
-- Name: quarantined_assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quarantined_assets (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    original_payload jsonb,
    rejection_reason text,
    status character varying,
    system_connector_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    asset_id uuid,
    reviewed_by_id bigint,
    reviewed_at timestamp(6) without time zone,
    review_notes text
);


--
-- Name: quarantined_assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.quarantined_assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: quarantined_assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.quarantined_assets_id_seq OWNED BY public.quarantined_assets.id;


--
-- Name: renditions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.renditions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    asset_id uuid NOT NULL,
    content_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    file_size bigint,
    height integer,
    kind character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    storage_backend_id uuid NOT NULL,
    storage_key character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    width integer
);


--
-- Name: report_definitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_definitions (
    id bigint NOT NULL,
    active boolean,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying,
    query_config jsonb,
    report_type character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: report_definitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.report_definitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_definitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.report_definitions_id_seq OWNED BY public.report_definitions.id;


--
-- Name: report_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_snapshots (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    error_message text,
    format character varying NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb,
    report_definition_id bigint NOT NULL,
    status integer DEFAULT 0,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: report_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.report_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.report_snapshots_id_seq OWNED BY public.report_snapshots.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    key character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    value text
);


--
-- Name: settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.settings_id_seq OWNED BY public.settings.id;


--
-- Name: storage_backends; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.storage_backends (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    active boolean DEFAULT true,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    provider_type character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: style_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.style_presets (
    id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id bigint,
    description text,
    gateway_ref character varying,
    is_default boolean DEFAULT false NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    style_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    synced_at timestamp(6) without time zone,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: style_presets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.style_presets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: style_presets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.style_presets_id_seq OWNED BY public.style_presets.id;


--
-- Name: system_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_configurations (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    data_type character varying DEFAULT 'string'::character varying NOT NULL,
    description character varying,
    expires_at timestamp(6) without time zone,
    fallback_value text,
    key character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    updated_by_id integer,
    value text NOT NULL
);


--
-- Name: system_configurations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_configurations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_configurations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_configurations_id_seq OWNED BY public.system_configurations.id;


--
-- Name: system_connectors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_connectors (
    id bigint NOT NULL,
    analysis_report jsonb,
    assets_imported integer,
    auth_token character varying,
    concurrency_limit integer,
    created_at timestamp(6) without time zone NOT NULL,
    endpoint character varying,
    last_sync timestamp(6) without time zone,
    name character varying,
    provider_type character varying,
    rps_limit integer,
    status character varying,
    tdm_sanitation boolean,
    updated_at timestamp(6) without time zone NOT NULL,
    webhook_secret character varying,
    credential_type character varying DEFAULT 'token'::character varying NOT NULL,
    credentials_payload text,
    access_token character varying,
    access_token_expires_at timestamp(6) without time zone,
    token_status character varying DEFAULT 'not_configured'::character varying NOT NULL,
    last_token_refreshed_at timestamp(6) without time zone,
    last_token_error text,
    default_source_path character varying
);


--
-- Name: system_connectors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.system_connectors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: system_connectors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.system_connectors_id_seq OWNED BY public.system_connectors.id;


--
-- Name: transformation_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transformation_presets (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying,
    params jsonb,
    slug character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: transformation_presets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.transformation_presets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: transformation_presets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.transformation_presets_id_seq OWNED BY public.transformation_presets.id;


--
-- Name: user_group_closures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_group_closures (
    ancestor_id bigint NOT NULL,
    descendant_id bigint NOT NULL,
    distance integer NOT NULL
);


--
-- Name: user_group_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_group_memberships (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_group_id bigint NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: user_group_memberships_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_group_memberships_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_group_memberships_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_group_memberships_id_seq OWNED BY public.user_group_memberships.id;


--
-- Name: user_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_groups (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    description character varying,
    is_system boolean DEFAULT false NOT NULL,
    name character varying NOT NULL,
    parent_id bigint,
    slug character varying,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_groups_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_groups_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_groups_id_seq OWNED BY public.user_groups.id;


--
-- Name: user_impersonators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_impersonators (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    impersonator_id bigint NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: user_impersonators_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_impersonators_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_impersonators_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_impersonators_id_seq OWNED BY public.user_impersonators.id;


--
-- Name: user_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_preferences (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    language character varying DEFAULT 'en'::character varying NOT NULL,
    receive_mention_emails boolean DEFAULT true NOT NULL,
    receive_workflow_emails boolean DEFAULT true NOT NULL,
    theme character varying DEFAULT 'system'::character varying NOT NULL,
    timezone character varying DEFAULT 'UTC'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL
);


--
-- Name: user_preferences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_preferences_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_preferences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_preferences_id_seq OWNED BY public.user_preferences.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    active boolean DEFAULT true,
    admin boolean DEFAULT false NOT NULL,
    avatar_url character varying,
    created_at timestamp(6) without time zone NOT NULL,
    department character varying,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    first_name character varying,
    force_password_change boolean DEFAULT false,
    last_name character varying,
    name character varying NOT NULL,
    preferences jsonb DEFAULT '{}'::jsonb,
    provider character varying,
    remember_created_at timestamp(6) without time zone,
    reset_password_sent_at timestamp(6) without time zone,
    reset_password_token character varying,
    role character varying DEFAULT 'viewer'::character varying,
    uid character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    username character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: video_encoding_presets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_encoding_presets (
    id bigint NOT NULL,
    advanced_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    audio_bitrate_kbps integer DEFAULT 128 NOT NULL,
    audio_codec character varying DEFAULT 'he_aac'::character varying NOT NULL,
    audio_sampling_rate integer,
    constant_bitrate boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    frame_rate_fps integer DEFAULT 30 NOT NULL,
    h264_profile character varying,
    height integer NOT NULL,
    keep_aspect_ratio boolean DEFAULT true NOT NULL,
    name character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    two_pass_encoding boolean DEFAULT false NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_bitrate_kbps integer NOT NULL,
    video_format_codec character varying DEFAULT 'h264'::character varying NOT NULL,
    video_profile_id bigint NOT NULL,
    width integer
);


--
-- Name: COLUMN video_encoding_presets.video_format_codec; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.video_encoding_presets.video_format_codec IS 'mp4 h.264 = h264';


--
-- Name: video_encoding_presets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_encoding_presets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_encoding_presets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_encoding_presets_id_seq OWNED BY public.video_encoding_presets.id;


--
-- Name: video_profile_folder_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_profile_folder_assignments (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    folder_id uuid NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    video_profile_id bigint NOT NULL
);


--
-- Name: video_profile_folder_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_profile_folder_assignments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_profile_folder_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_profile_folder_assignments_id_seq OWNED BY public.video_profile_folder_assignments.id;


--
-- Name: video_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.video_profiles (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    deleted_at timestamp(6) without time zone,
    description text,
    encode_for_adaptive_streaming boolean DEFAULT true NOT NULL,
    name character varying NOT NULL,
    smart_crop_ratios jsonb DEFAULT '[]'::jsonb NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: video_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.video_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: video_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.video_profiles_id_seq OWNED BY public.video_profiles.id;


--
-- Name: workflow_instances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_instances (
    id bigint NOT NULL,
    asset_id uuid NOT NULL,
    audit_log jsonb,
    blueprint_snapshot jsonb DEFAULT '{}'::jsonb,
    cancel_reason text,
    cancelled_by_id bigint,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    current_step_id integer,
    last_action_by_id integer,
    started_at timestamp(6) without time zone,
    status character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    workflow_id bigint NOT NULL
);


--
-- Name: workflow_instances_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workflow_instances_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workflow_instances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workflow_instances_id_seq OWNED BY public.workflow_instances.id;


--
-- Name: workflow_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_steps (
    id bigint NOT NULL,
    assignee_id integer,
    assignee_type character varying,
    configuration jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    deadline_days integer,
    description text,
    fallback_assignee_id character varying DEFAULT ''::character varying,
    fallback_assignee_type character varying DEFAULT 'user'::character varying,
    logic character varying,
    node_type character varying DEFAULT 'approval'::character varying NOT NULL,
    "position" integer,
    step_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    step_type character varying,
    title character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    updated_by_id integer,
    workflow_id bigint NOT NULL
);


--
-- Name: workflow_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workflow_steps_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workflow_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workflow_steps_id_seq OWNED BY public.workflow_steps.id;


--
-- Name: workflow_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_tasks (
    id bigint NOT NULL,
    comment text,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    user_id bigint NOT NULL,
    workflow_instance_id bigint NOT NULL,
    workflow_step_id bigint NOT NULL
);


--
-- Name: workflow_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workflow_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workflow_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workflow_tasks_id_seq OWNED BY public.workflow_tasks.id;


--
-- Name: workflows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflows (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    created_by_id integer,
    description text,
    exclude_folder_ids character varying[] DEFAULT '{}'::character varying[],
    fallback_assignee_id character varying,
    fallback_assignee_type character varying,
    folder_scope character varying DEFAULT 'all'::character varying,
    graph_data jsonb DEFAULT '{}'::jsonb,
    metadata jsonb,
    name character varying,
    status integer,
    target_folder_ids character varying[] DEFAULT '{}'::character varying[],
    trigger_type character varying,
    updated_at timestamp(6) without time zone NOT NULL,
    updated_by_id integer
);


--
-- Name: workflows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.workflows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: workflows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.workflows_id_seq OWNED BY public.workflows.id;


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: agent_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_executions ALTER COLUMN id SET DEFAULT nextval('public.agent_executions_id_seq'::regclass);


--
-- Name: agent_workflows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_workflows ALTER COLUMN id SET DEFAULT nextval('public.agent_workflows_id_seq'::regclass);


--
-- Name: ai_batch_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_batch_jobs ALTER COLUMN id SET DEFAULT nextval('public.ai_batch_jobs_id_seq'::regclass);


--
-- Name: ai_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_configurations ALTER COLUMN id SET DEFAULT nextval('public.ai_configurations_id_seq'::regclass);


--
-- Name: ai_model_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_model_configs ALTER COLUMN id SET DEFAULT nextval('public.ai_model_configs_id_seq'::regclass);


--
-- Name: asset_provenance_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_provenance_records ALTER COLUMN id SET DEFAULT nextval('public.asset_provenance_records_id_seq'::regclass);


--
-- Name: audit_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs ALTER COLUMN id SET DEFAULT nextval('public.audit_logs_id_seq'::regclass);


--
-- Name: c2pa_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.c2pa_configurations ALTER COLUMN id SET DEFAULT nextval('public.c2pa_configurations_id_seq'::regclass);


--
-- Name: cdn_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cdn_configurations ALTER COLUMN id SET DEFAULT nextval('public.cdn_configurations_id_seq'::regclass);


--
-- Name: collection_assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_assets ALTER COLUMN id SET DEFAULT nextval('public.collection_assets_id_seq'::regclass);


--
-- Name: collection_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_rules ALTER COLUMN id SET DEFAULT nextval('public.collection_rules_id_seq'::regclass);


--
-- Name: collections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collections ALTER COLUMN id SET DEFAULT nextval('public.collections_id_seq'::regclass);


--
-- Name: custom_node_definitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_node_definitions ALTER COLUMN id SET DEFAULT nextval('public.custom_node_definitions_id_seq'::regclass);


--
-- Name: daily_metrics id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_metrics ALTER COLUMN id SET DEFAULT nextval('public.daily_metrics_id_seq'::regclass);


--
-- Name: duplicate_group_assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_group_assets ALTER COLUMN id SET DEFAULT nextval('public.duplicate_group_assets_id_seq'::regclass);


--
-- Name: email_deliveries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_deliveries ALTER COLUMN id SET DEFAULT nextval('public.email_deliveries_id_seq'::regclass);


--
-- Name: email_templates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates ALTER COLUMN id SET DEFAULT nextval('public.email_templates_id_seq'::regclass);


--
-- Name: folder_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_policies ALTER COLUMN id SET DEFAULT nextval('public.folder_policies_id_seq'::regclass);


--
-- Name: image_profile_folder_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_profile_folder_assignments ALTER COLUMN id SET DEFAULT nextval('public.image_profile_folder_assignments_id_seq'::regclass);


--
-- Name: image_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_profiles ALTER COLUMN id SET DEFAULT nextval('public.image_profiles_id_seq'::regclass);


--
-- Name: in_app_notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.in_app_notifications ALTER COLUMN id SET DEFAULT nextval('public.in_app_notifications_id_seq'::regclass);


--
-- Name: metadata_exports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_exports ALTER COLUMN id SET DEFAULT nextval('public.metadata_exports_id_seq'::regclass);


--
-- Name: metadata_imports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_imports ALTER COLUMN id SET DEFAULT nextval('public.metadata_imports_id_seq'::regclass);


--
-- Name: metadata_schema_folder_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schema_folder_assignments ALTER COLUMN id SET DEFAULT nextval('public.metadata_schema_folder_assignments_id_seq'::regclass);


--
-- Name: metadata_schemas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schemas ALTER COLUMN id SET DEFAULT nextval('public.metadata_schemas_id_seq'::regclass);


--
-- Name: notifications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications ALTER COLUMN id SET DEFAULT nextval('public.notifications_id_seq'::regclass);


--
-- Name: oauth_access_grants id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_grants_id_seq'::regclass);


--
-- Name: oauth_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.oauth_access_tokens_id_seq'::regclass);


--
-- Name: oauth_applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications ALTER COLUMN id SET DEFAULT nextval('public.oauth_applications_id_seq'::regclass);


--
-- Name: personal_access_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens ALTER COLUMN id SET DEFAULT nextval('public.personal_access_tokens_id_seq'::regclass);


--
-- Name: quarantined_assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quarantined_assets ALTER COLUMN id SET DEFAULT nextval('public.quarantined_assets_id_seq'::regclass);


--
-- Name: report_definitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_definitions ALTER COLUMN id SET DEFAULT nextval('public.report_definitions_id_seq'::regclass);


--
-- Name: report_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_snapshots ALTER COLUMN id SET DEFAULT nextval('public.report_snapshots_id_seq'::regclass);


--
-- Name: settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings ALTER COLUMN id SET DEFAULT nextval('public.settings_id_seq'::regclass);


--
-- Name: style_presets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.style_presets ALTER COLUMN id SET DEFAULT nextval('public.style_presets_id_seq'::regclass);


--
-- Name: system_configurations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_configurations ALTER COLUMN id SET DEFAULT nextval('public.system_configurations_id_seq'::regclass);


--
-- Name: system_connectors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_connectors ALTER COLUMN id SET DEFAULT nextval('public.system_connectors_id_seq'::regclass);


--
-- Name: transformation_presets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transformation_presets ALTER COLUMN id SET DEFAULT nextval('public.transformation_presets_id_seq'::regclass);


--
-- Name: user_group_memberships id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_group_memberships ALTER COLUMN id SET DEFAULT nextval('public.user_group_memberships_id_seq'::regclass);


--
-- Name: user_groups id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_groups ALTER COLUMN id SET DEFAULT nextval('public.user_groups_id_seq'::regclass);


--
-- Name: user_impersonators id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_impersonators ALTER COLUMN id SET DEFAULT nextval('public.user_impersonators_id_seq'::regclass);


--
-- Name: user_preferences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences ALTER COLUMN id SET DEFAULT nextval('public.user_preferences_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: video_encoding_presets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_encoding_presets ALTER COLUMN id SET DEFAULT nextval('public.video_encoding_presets_id_seq'::regclass);


--
-- Name: video_profile_folder_assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_profile_folder_assignments ALTER COLUMN id SET DEFAULT nextval('public.video_profile_folder_assignments_id_seq'::regclass);


--
-- Name: video_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_profiles ALTER COLUMN id SET DEFAULT nextval('public.video_profiles_id_seq'::regclass);


--
-- Name: workflow_instances id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_instances ALTER COLUMN id SET DEFAULT nextval('public.workflow_instances_id_seq'::regclass);


--
-- Name: workflow_steps id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_steps ALTER COLUMN id SET DEFAULT nextval('public.workflow_steps_id_seq'::regclass);


--
-- Name: workflow_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_tasks ALTER COLUMN id SET DEFAULT nextval('public.workflow_tasks_id_seq'::regclass);


--
-- Name: workflows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows ALTER COLUMN id SET DEFAULT nextval('public.workflows_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: agent_executions agent_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_executions
    ADD CONSTRAINT agent_executions_pkey PRIMARY KEY (id);


--
-- Name: agent_workflows agent_workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_workflows
    ADD CONSTRAINT agent_workflows_pkey PRIMARY KEY (id);


--
-- Name: ai_batch_jobs ai_batch_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_batch_jobs
    ADD CONSTRAINT ai_batch_jobs_pkey PRIMARY KEY (id);


--
-- Name: ai_configurations ai_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_configurations
    ADD CONSTRAINT ai_configurations_pkey PRIMARY KEY (id);


--
-- Name: ai_model_configs ai_model_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_model_configs
    ADD CONSTRAINT ai_model_configs_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: asset_embeddings asset_embeddings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_embeddings
    ADD CONSTRAINT asset_embeddings_pkey PRIMARY KEY (id);


--
-- Name: asset_provenance_records asset_provenance_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_provenance_records
    ADD CONSTRAINT asset_provenance_records_pkey PRIMARY KEY (id);


--
-- Name: asset_usage_events asset_usage_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_usage_events
    ADD CONSTRAINT asset_usage_events_pkey PRIMARY KEY (id);


--
-- Name: asset_versions asset_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_versions
    ADD CONSTRAINT asset_versions_pkey PRIMARY KEY (id);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: c2pa_configurations c2pa_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.c2pa_configurations
    ADD CONSTRAINT c2pa_configurations_pkey PRIMARY KEY (id);


--
-- Name: cdn_configurations cdn_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cdn_configurations
    ADD CONSTRAINT cdn_configurations_pkey PRIMARY KEY (id);


--
-- Name: collection_assets collection_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_assets
    ADD CONSTRAINT collection_assets_pkey PRIMARY KEY (id);


--
-- Name: collection_rules collection_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_rules
    ADD CONSTRAINT collection_rules_pkey PRIMARY KEY (id);


--
-- Name: collections collections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collections
    ADD CONSTRAINT collections_pkey PRIMARY KEY (id);


--
-- Name: custom_node_definitions custom_node_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_node_definitions
    ADD CONSTRAINT custom_node_definitions_pkey PRIMARY KEY (id);


--
-- Name: daily_metrics daily_metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.daily_metrics
    ADD CONSTRAINT daily_metrics_pkey PRIMARY KEY (id);


--
-- Name: duplicate_group_assets duplicate_group_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_group_assets
    ADD CONSTRAINT duplicate_group_assets_pkey PRIMARY KEY (id);


--
-- Name: duplicate_groups duplicate_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_groups
    ADD CONSTRAINT duplicate_groups_pkey PRIMARY KEY (id);


--
-- Name: email_deliveries email_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_deliveries
    ADD CONSTRAINT email_deliveries_pkey PRIMARY KEY (id);


--
-- Name: email_templates email_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (id);


--
-- Name: folder_policies folder_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_policies
    ADD CONSTRAINT folder_policies_pkey PRIMARY KEY (id);


--
-- Name: folders folders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folders
    ADD CONSTRAINT folders_pkey PRIMARY KEY (id);


--
-- Name: image_profile_folder_assignments image_profile_folder_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_profile_folder_assignments
    ADD CONSTRAINT image_profile_folder_assignments_pkey PRIMARY KEY (id);


--
-- Name: image_profiles image_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_profiles
    ADD CONSTRAINT image_profiles_pkey PRIMARY KEY (id);


--
-- Name: in_app_notifications in_app_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.in_app_notifications
    ADD CONSTRAINT in_app_notifications_pkey PRIMARY KEY (id);


--
-- Name: inbox_messages inbox_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_messages
    ADD CONSTRAINT inbox_messages_pkey PRIMARY KEY (id);


--
-- Name: ingestion_batches ingestion_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_batches
    ADD CONSTRAINT ingestion_batches_pkey PRIMARY KEY (id);


--
-- Name: ingestion_items ingestion_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_items
    ADD CONSTRAINT ingestion_items_pkey PRIMARY KEY (id);


--
-- Name: metadata_exports metadata_exports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_exports
    ADD CONSTRAINT metadata_exports_pkey PRIMARY KEY (id);


--
-- Name: metadata_imports metadata_imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_imports
    ADD CONSTRAINT metadata_imports_pkey PRIMARY KEY (id);


--
-- Name: metadata_schema_folder_assignments metadata_schema_folder_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schema_folder_assignments
    ADD CONSTRAINT metadata_schema_folder_assignments_pkey PRIMARY KEY (id);


--
-- Name: metadata_schemas metadata_schemas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schemas
    ADD CONSTRAINT metadata_schemas_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_grants oauth_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT oauth_access_grants_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_tokens oauth_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT oauth_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth_applications oauth_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_applications
    ADD CONSTRAINT oauth_applications_pkey PRIMARY KEY (id);


--
-- Name: personal_access_tokens personal_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.personal_access_tokens
    ADD CONSTRAINT personal_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: quarantined_assets quarantined_assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quarantined_assets
    ADD CONSTRAINT quarantined_assets_pkey PRIMARY KEY (id);


--
-- Name: renditions renditions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renditions
    ADD CONSTRAINT renditions_pkey PRIMARY KEY (id);


--
-- Name: report_definitions report_definitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_definitions
    ADD CONSTRAINT report_definitions_pkey PRIMARY KEY (id);


--
-- Name: report_snapshots report_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_snapshots
    ADD CONSTRAINT report_snapshots_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: settings settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings
    ADD CONSTRAINT settings_pkey PRIMARY KEY (id);


--
-- Name: storage_backends storage_backends_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.storage_backends
    ADD CONSTRAINT storage_backends_pkey PRIMARY KEY (id);


--
-- Name: style_presets style_presets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.style_presets
    ADD CONSTRAINT style_presets_pkey PRIMARY KEY (id);


--
-- Name: system_configurations system_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_configurations
    ADD CONSTRAINT system_configurations_pkey PRIMARY KEY (id);


--
-- Name: system_connectors system_connectors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_connectors
    ADD CONSTRAINT system_connectors_pkey PRIMARY KEY (id);


--
-- Name: transformation_presets transformation_presets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transformation_presets
    ADD CONSTRAINT transformation_presets_pkey PRIMARY KEY (id);


--
-- Name: user_group_memberships user_group_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_group_memberships
    ADD CONSTRAINT user_group_memberships_pkey PRIMARY KEY (id);


--
-- Name: user_groups user_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_groups
    ADD CONSTRAINT user_groups_pkey PRIMARY KEY (id);


--
-- Name: user_impersonators user_impersonators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_impersonators
    ADD CONSTRAINT user_impersonators_pkey PRIMARY KEY (id);


--
-- Name: user_preferences user_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences
    ADD CONSTRAINT user_preferences_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: video_encoding_presets video_encoding_presets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_encoding_presets
    ADD CONSTRAINT video_encoding_presets_pkey PRIMARY KEY (id);


--
-- Name: video_profile_folder_assignments video_profile_folder_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_profile_folder_assignments
    ADD CONSTRAINT video_profile_folder_assignments_pkey PRIMARY KEY (id);


--
-- Name: video_profiles video_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_profiles
    ADD CONSTRAINT video_profiles_pkey PRIMARY KEY (id);


--
-- Name: workflow_instances workflow_instances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT workflow_instances_pkey PRIMARY KEY (id);


--
-- Name: workflow_steps workflow_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_steps
    ADD CONSTRAINT workflow_steps_pkey PRIMARY KEY (id);


--
-- Name: workflow_tasks workflow_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_tasks
    ADD CONSTRAINT workflow_tasks_pkey PRIMARY KEY (id);


--
-- Name: workflows workflows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflows
    ADD CONSTRAINT workflows_pkey PRIMARY KEY (id);


--
-- Name: idx_audit_logs_polymorphic_ip_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_logs_polymorphic_ip_user ON public.audit_logs USING btree (auditable_type, auditable_id, ip_address, user_id);


--
-- Name: idx_dup_group_assets_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_dup_group_assets_unique ON public.duplicate_group_assets USING btree (duplicate_group_id, asset_id);


--
-- Name: idx_group_closures_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_group_closures_pk ON public.user_group_closures USING btree (ancestor_id, descendant_id);


--
-- Name: idx_image_profile_folder_assignments_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_image_profile_folder_assignments_unique ON public.image_profile_folder_assignments USING btree (image_profile_id, folder_id);


--
-- Name: idx_metadata_schemas_parent_mime_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_metadata_schemas_parent_mime_unique ON public.metadata_schemas USING btree (parent_id, mime_segment) WHERE ((deleted_at IS NULL) AND (mime_segment IS NOT NULL));


--
-- Name: idx_schema_folder_on_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_schema_folder_on_folder_id ON public.metadata_schema_folder_assignments USING btree (folder_id);


--
-- Name: idx_schema_folder_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_schema_folder_unique ON public.metadata_schema_folder_assignments USING btree (metadata_schema_id, folder_id);


--
-- Name: idx_video_profile_folder_assignments_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_video_profile_folder_assignments_unique ON public.video_profile_folder_assignments USING btree (video_profile_id, folder_id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_agent_executions_on_agent_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_executions_on_agent_workflow_id ON public.agent_executions USING btree (agent_workflow_id);


--
-- Name: index_agent_executions_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_executions_on_started_at ON public.agent_executions USING btree (started_at);


--
-- Name: index_agent_executions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_executions_on_status ON public.agent_executions USING btree (status);


--
-- Name: index_agent_workflows_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_workflows_on_active ON public.agent_workflows USING btree (active);


--
-- Name: index_agent_workflows_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_workflows_on_created_by_id ON public.agent_workflows USING btree (created_by_id);


--
-- Name: index_agent_workflows_on_trigger_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_agent_workflows_on_trigger_event ON public.agent_workflows USING btree (trigger_event);


--
-- Name: index_ai_batch_jobs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_batch_jobs_on_created_at ON public.ai_batch_jobs USING btree (created_at);


--
-- Name: index_ai_batch_jobs_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_batch_jobs_on_created_by_id ON public.ai_batch_jobs USING btree (created_by_id);


--
-- Name: index_ai_batch_jobs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_batch_jobs_on_status ON public.ai_batch_jobs USING btree (status);


--
-- Name: index_ai_batch_jobs_on_task_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_batch_jobs_on_task_type ON public.ai_batch_jobs USING btree (task_type);


--
-- Name: index_ai_model_configs_on_capability; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_model_configs_on_capability ON public.ai_model_configs USING btree (capability);


--
-- Name: index_ai_model_configs_on_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_model_configs_on_enabled ON public.ai_model_configs USING btree (enabled);


--
-- Name: index_ai_model_configs_on_health_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_model_configs_on_health_status ON public.ai_model_configs USING btree (health_status);


--
-- Name: index_ai_model_configs_on_is_default; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_model_configs_on_is_default ON public.ai_model_configs USING btree (is_default);


--
-- Name: index_ai_model_configs_on_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_model_configs_on_provider ON public.ai_model_configs USING btree (provider);


--
-- Name: index_ai_model_configs_one_default_per_capability; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_model_configs_one_default_per_capability ON public.ai_model_configs USING btree (capability, is_default) WHERE (is_default = true);


--
-- Name: index_asset_embeddings_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_asset_embeddings_on_asset_id ON public.asset_embeddings USING btree (asset_id);


--
-- Name: index_asset_embeddings_on_embedding; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_embeddings_on_embedding ON public.asset_embeddings USING hnsw (embedding public.vector_cosine_ops);


--
-- Name: index_asset_provenance_records_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_asset_provenance_records_on_asset_id ON public.asset_provenance_records USING btree (asset_id);


--
-- Name: index_asset_provenance_records_on_is_ai_modified; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_provenance_records_on_is_ai_modified ON public.asset_provenance_records USING btree (is_ai_modified);


--
-- Name: index_asset_provenance_records_on_manifest_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_provenance_records_on_manifest_status ON public.asset_provenance_records USING btree (manifest_status);


--
-- Name: index_asset_provenance_records_on_verified_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_provenance_records_on_verified_at ON public.asset_provenance_records USING btree (verified_at);


--
-- Name: index_asset_usage_events_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_usage_events_on_asset_id ON public.asset_usage_events USING btree (asset_id);


--
-- Name: index_asset_usage_events_on_asset_id_and_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_usage_events_on_asset_id_and_event_type ON public.asset_usage_events USING btree (asset_id, event_type);


--
-- Name: index_asset_usage_events_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_usage_events_on_user_id ON public.asset_usage_events USING btree (user_id);


--
-- Name: index_asset_versions_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_versions_on_asset_id ON public.asset_versions USING btree (asset_id);


--
-- Name: index_asset_versions_on_asset_id_and_version_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_asset_versions_on_asset_id_and_version_number ON public.asset_versions USING btree (asset_id, version_number);


--
-- Name: index_asset_versions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_asset_versions_on_created_by_id ON public.asset_versions USING btree (created_by_id);


--
-- Name: index_assets_on_active_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_active_version_id ON public.assets USING btree (active_version_id);


--
-- Name: index_assets_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_deleted_at ON public.assets USING btree (deleted_at);


--
-- Name: index_assets_on_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_folder_id ON public.assets USING btree (folder_id);


--
-- Name: index_assets_on_folder_id_and_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_folder_id_and_deleted_at ON public.assets USING btree (folder_id, deleted_at);


--
-- Name: index_assets_on_properties; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_properties ON public.assets USING gin (properties);


--
-- Name: index_assets_on_properties_applied_schema_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_properties_applied_schema_id ON public.assets USING btree (((properties ->> 'applied_schema_id'::text)));


--
-- Name: index_assets_on_properties_content_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_properties_content_type ON public.assets USING btree (((properties ->> 'content_type'::text)));


--
-- Name: index_assets_on_properties_file_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_properties_file_size ON public.assets USING btree ((((properties ->> 'file_size'::text))::bigint)) WHERE ((properties ->> 'file_size'::text) ~ '^[0-9]+$'::text);


--
-- Name: index_assets_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_user_id ON public.assets USING btree (user_id);


--
-- Name: index_assets_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assets_on_uuid ON public.assets USING btree (uuid);


--
-- Name: index_audit_logs_on_true_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_true_user_id ON public.audit_logs USING btree (true_user_id);


--
-- Name: index_audit_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_logs_on_user_id ON public.audit_logs USING btree (user_id);


--
-- Name: index_collection_assets_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collection_assets_on_asset_id ON public.collection_assets USING btree (asset_id);


--
-- Name: index_collection_assets_on_collection_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collection_assets_on_collection_id ON public.collection_assets USING btree (collection_id);


--
-- Name: index_collection_assets_on_collection_id_and_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_collection_assets_on_collection_id_and_asset_id ON public.collection_assets USING btree (collection_id, asset_id);


--
-- Name: index_collection_assets_on_collection_rule_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collection_assets_on_collection_rule_id ON public.collection_assets USING btree (collection_rule_id);


--
-- Name: index_collection_rules_on_collection_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collection_rules_on_collection_id ON public.collection_rules USING btree (collection_id);


--
-- Name: index_collection_rules_on_metadata_filters; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collection_rules_on_metadata_filters ON public.collection_rules USING gin (metadata_filters);


--
-- Name: index_collections_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_collections_on_slug ON public.collections USING btree (slug);


--
-- Name: index_collections_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_collections_on_uuid ON public.collections USING btree (uuid);


--
-- Name: index_custom_node_definitions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_custom_node_definitions_on_created_by_id ON public.custom_node_definitions USING btree (created_by_id);


--
-- Name: index_custom_node_definitions_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_custom_node_definitions_on_key ON public.custom_node_definitions USING btree (key);


--
-- Name: index_daily_metrics_on_metric_date_and_metric_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_daily_metrics_on_metric_date_and_metric_name ON public.daily_metrics USING btree (metric_date, metric_name);


--
-- Name: index_duplicate_group_assets_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_duplicate_group_assets_on_asset_id ON public.duplicate_group_assets USING btree (asset_id);


--
-- Name: index_duplicate_group_assets_on_duplicate_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_duplicate_group_assets_on_duplicate_group_id ON public.duplicate_group_assets USING btree (duplicate_group_id);


--
-- Name: index_duplicate_groups_on_checksum; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_duplicate_groups_on_checksum ON public.duplicate_groups USING btree (checksum);


--
-- Name: index_duplicate_groups_on_resolved_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_duplicate_groups_on_resolved_by_id ON public.duplicate_groups USING btree (resolved_by_id);


--
-- Name: index_duplicate_groups_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_duplicate_groups_on_status ON public.duplicate_groups USING btree (status);


--
-- Name: index_email_deliveries_on_email_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_deliveries_on_email_template_id ON public.email_deliveries USING btree (email_template_id);


--
-- Name: index_email_deliveries_on_recipient_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_deliveries_on_recipient_email ON public.email_deliveries USING btree (recipient_email);


--
-- Name: index_email_deliveries_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_deliveries_on_status ON public.email_deliveries USING btree (status);


--
-- Name: index_email_templates_on_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_templates_on_category ON public.email_templates USING btree (category);


--
-- Name: index_email_templates_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_email_templates_on_created_by_id ON public.email_templates USING btree (created_by_id);


--
-- Name: index_email_templates_on_event_trigger; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_email_templates_on_event_trigger ON public.email_templates USING btree (event_trigger);


--
-- Name: index_folder_policies_on_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folder_policies_on_folder_id ON public.folder_policies USING btree (folder_id);


--
-- Name: index_folder_policies_on_folder_id_and_user_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_folder_policies_on_folder_id_and_user_group_id ON public.folder_policies USING btree (folder_id, user_group_id);


--
-- Name: index_folder_policies_on_user_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folder_policies_on_user_group_id ON public.folder_policies USING btree (user_group_id);


--
-- Name: index_folders_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folders_on_deleted_at ON public.folders USING btree (deleted_at);


--
-- Name: index_folders_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folders_on_parent_id ON public.folders USING btree (parent_id);


--
-- Name: index_folders_on_parent_id_and_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folders_on_parent_id_and_deleted_at ON public.folders USING btree (parent_id, deleted_at);


--
-- Name: index_folders_on_path; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folders_on_path ON public.folders USING btree (path);


--
-- Name: index_folders_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folders_on_slug ON public.folders USING btree (slug);


--
-- Name: index_folders_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_folders_on_user_id ON public.folders USING btree (user_id);


--
-- Name: index_folders_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_folders_on_uuid ON public.folders USING btree (uuid);


--
-- Name: index_image_profile_folder_assignments_on_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_profile_folder_assignments_on_folder_id ON public.image_profile_folder_assignments USING btree (folder_id);


--
-- Name: index_image_profile_folder_assignments_on_image_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_profile_folder_assignments_on_image_profile_id ON public.image_profile_folder_assignments USING btree (image_profile_id);


--
-- Name: index_image_profiles_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_profiles_on_deleted_at ON public.image_profiles USING btree (deleted_at);


--
-- Name: index_image_profiles_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_profiles_on_name ON public.image_profiles USING btree (name);


--
-- Name: index_in_app_notifications_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_in_app_notifications_on_actor_id ON public.in_app_notifications USING btree (actor_id);


--
-- Name: index_in_app_notifications_on_notifiable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_in_app_notifications_on_notifiable ON public.in_app_notifications USING btree (notifiable_type, notifiable_id);


--
-- Name: index_in_app_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_in_app_notifications_on_user_id ON public.in_app_notifications USING btree (user_id);


--
-- Name: index_in_app_notifications_on_user_id_and_read_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_in_app_notifications_on_user_id_and_read_at ON public.in_app_notifications USING btree (user_id, read_at);


--
-- Name: index_inbox_messages_on_email_template_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_messages_on_email_template_id ON public.inbox_messages USING btree (email_template_id);


--
-- Name: index_inbox_messages_on_message_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_messages_on_message_type ON public.inbox_messages USING btree (message_type);


--
-- Name: index_inbox_messages_on_recipient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_messages_on_recipient_id ON public.inbox_messages USING btree (recipient_id);


--
-- Name: index_inbox_messages_on_recipient_id_and_archived_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_messages_on_recipient_id_and_archived_at ON public.inbox_messages USING btree (recipient_id, archived_at);


--
-- Name: index_inbox_messages_on_recipient_id_and_read_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_messages_on_recipient_id_and_read_at ON public.inbox_messages USING btree (recipient_id, read_at);


--
-- Name: index_inbox_messages_on_sender_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_inbox_messages_on_sender_id ON public.inbox_messages USING btree (sender_id);


--
-- Name: index_ingestion_batches_on_connector_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_batches_on_connector_id ON public.ingestion_batches USING btree (connector_id);


--
-- Name: index_ingestion_batches_on_destination_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_batches_on_destination_folder_id ON public.ingestion_batches USING btree (destination_folder_id);


--
-- Name: index_ingestion_items_on_file_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_items_on_file_hash ON public.ingestion_items USING btree (file_hash);


--
-- Name: index_ingestion_items_on_ingestion_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ingestion_items_on_ingestion_batch_id ON public.ingestion_items USING btree (ingestion_batch_id);


--
-- Name: index_metadata_exports_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_exports_on_expires_at ON public.metadata_exports USING btree (expires_at);


--
-- Name: index_metadata_exports_on_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_exports_on_folder_id ON public.metadata_exports USING btree (folder_id);


--
-- Name: index_metadata_exports_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_exports_on_status ON public.metadata_exports USING btree (status);


--
-- Name: index_metadata_exports_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_exports_on_user_id ON public.metadata_exports USING btree (user_id);


--
-- Name: index_metadata_imports_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_imports_on_expires_at ON public.metadata_imports USING btree (expires_at);


--
-- Name: index_metadata_imports_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_imports_on_status ON public.metadata_imports USING btree (status);


--
-- Name: index_metadata_imports_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_imports_on_user_id ON public.metadata_imports USING btree (user_id);


--
-- Name: index_metadata_schemas_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_schemas_on_deleted_at ON public.metadata_schemas USING btree (deleted_at);


--
-- Name: index_metadata_schemas_on_inherits_from_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_schemas_on_inherits_from_id ON public.metadata_schemas USING btree (inherits_from_id);


--
-- Name: index_metadata_schemas_on_is_builtin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_schemas_on_is_builtin ON public.metadata_schemas USING btree (is_builtin);


--
-- Name: index_metadata_schemas_on_level; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_schemas_on_level ON public.metadata_schemas USING btree (level);


--
-- Name: index_metadata_schemas_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metadata_schemas_on_parent_id ON public.metadata_schemas USING btree (parent_id);


--
-- Name: index_metadata_schemas_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metadata_schemas_on_slug ON public.metadata_schemas USING btree (slug) WHERE (deleted_at IS NULL);


--
-- Name: index_metadata_schemas_on_uuid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_metadata_schemas_on_uuid ON public.metadata_schemas USING btree (uuid);


--
-- Name: index_notifications_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_user_id ON public.notifications USING btree (user_id);


--
-- Name: index_oauth_access_grants_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_application_id ON public.oauth_access_grants USING btree (application_id);


--
-- Name: index_oauth_access_grants_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_grants_on_resource_owner_id ON public.oauth_access_grants USING btree (resource_owner_id);


--
-- Name: index_oauth_access_grants_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON public.oauth_access_grants USING btree (token);


--
-- Name: index_oauth_access_tokens_on_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_application_id ON public.oauth_access_tokens USING btree (application_id);


--
-- Name: index_oauth_access_tokens_on_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON public.oauth_access_tokens USING btree (refresh_token);


--
-- Name: index_oauth_access_tokens_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON public.oauth_access_tokens USING btree (resource_owner_id);


--
-- Name: index_oauth_access_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON public.oauth_access_tokens USING btree (token);


--
-- Name: index_oauth_applications_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_uid ON public.oauth_applications USING btree (uid);


--
-- Name: index_personal_access_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_personal_access_tokens_on_token_digest ON public.personal_access_tokens USING btree (token_digest);


--
-- Name: index_personal_access_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_personal_access_tokens_on_user_id ON public.personal_access_tokens USING btree (user_id);


--
-- Name: index_personal_access_tokens_on_user_id_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_personal_access_tokens_on_user_id_and_active ON public.personal_access_tokens USING btree (user_id, active);


--
-- Name: index_quarantined_assets_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quarantined_assets_on_asset_id ON public.quarantined_assets USING btree (asset_id);


--
-- Name: index_quarantined_assets_on_reviewed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quarantined_assets_on_reviewed_by_id ON public.quarantined_assets USING btree (reviewed_by_id);


--
-- Name: index_quarantined_assets_on_system_connector_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quarantined_assets_on_system_connector_id ON public.quarantined_assets USING btree (system_connector_id);


--
-- Name: index_renditions_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_renditions_on_asset_id ON public.renditions USING btree (asset_id);


--
-- Name: index_renditions_on_storage_backend_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_renditions_on_storage_backend_id ON public.renditions USING btree (storage_backend_id);


--
-- Name: index_report_snapshots_on_report_definition_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_report_snapshots_on_report_definition_id ON public.report_snapshots USING btree (report_definition_id);


--
-- Name: index_settings_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_settings_on_key ON public.settings USING btree (key);


--
-- Name: index_style_presets_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_style_presets_on_active ON public.style_presets USING btree (active);


--
-- Name: index_style_presets_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_style_presets_on_created_by_id ON public.style_presets USING btree (created_by_id);


--
-- Name: index_style_presets_on_is_default; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_style_presets_on_is_default ON public.style_presets USING btree (is_default);


--
-- Name: index_style_presets_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_style_presets_on_slug ON public.style_presets USING btree (slug);


--
-- Name: index_system_configurations_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_system_configurations_on_key ON public.system_configurations USING btree (key);


--
-- Name: index_system_configurations_on_updated_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_system_configurations_on_updated_by_id ON public.system_configurations USING btree (updated_by_id);


--
-- Name: index_transformation_presets_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_transformation_presets_on_slug ON public.transformation_presets USING btree (slug);


--
-- Name: index_user_group_closures_on_descendant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_group_closures_on_descendant_id ON public.user_group_closures USING btree (descendant_id);


--
-- Name: index_user_group_memberships_on_user_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_group_memberships_on_user_group_id ON public.user_group_memberships USING btree (user_group_id);


--
-- Name: index_user_group_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_group_memberships_on_user_id ON public.user_group_memberships USING btree (user_id);


--
-- Name: index_user_group_memberships_on_user_id_and_user_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_group_memberships_on_user_id_and_user_group_id ON public.user_group_memberships USING btree (user_id, user_group_id);


--
-- Name: index_user_groups_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_groups_on_name ON public.user_groups USING btree (name);


--
-- Name: index_user_groups_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_groups_on_parent_id ON public.user_groups USING btree (parent_id);


--
-- Name: index_user_groups_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_groups_on_slug ON public.user_groups USING btree (slug);


--
-- Name: index_user_impersonators_on_impersonator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_impersonators_on_impersonator_id ON public.user_impersonators USING btree (impersonator_id);


--
-- Name: index_user_impersonators_on_pair; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_impersonators_on_pair ON public.user_impersonators USING btree (user_id, impersonator_id);


--
-- Name: index_user_impersonators_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_impersonators_on_user_id ON public.user_impersonators USING btree (user_id);


--
-- Name: index_user_preferences_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_preferences_on_user_id ON public.user_preferences USING btree (user_id);


--
-- Name: index_users_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_active ON public.users USING btree (active);


--
-- Name: index_users_on_department; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_department ON public.users USING btree (department);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_first_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_first_name ON public.users USING btree (first_name);


--
-- Name: index_users_on_last_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_name ON public.users USING btree (last_name);


--
-- Name: index_users_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_provider_and_uid ON public.users USING btree (provider, uid);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_role ON public.users USING btree (role);


--
-- Name: index_users_on_username; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_username ON public.users USING btree (username);


--
-- Name: index_video_encoding_presets_on_video_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_encoding_presets_on_video_profile_id ON public.video_encoding_presets USING btree (video_profile_id);


--
-- Name: index_video_profile_folder_assignments_on_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_profile_folder_assignments_on_folder_id ON public.video_profile_folder_assignments USING btree (folder_id);


--
-- Name: index_video_profile_folder_assignments_on_video_profile_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_profile_folder_assignments_on_video_profile_id ON public.video_profile_folder_assignments USING btree (video_profile_id);


--
-- Name: index_video_profiles_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_profiles_on_deleted_at ON public.video_profiles USING btree (deleted_at);


--
-- Name: index_video_profiles_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_video_profiles_on_name ON public.video_profiles USING btree (name);


--
-- Name: index_workflow_instances_on_asset_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_instances_on_asset_id ON public.workflow_instances USING btree (asset_id);


--
-- Name: index_workflow_instances_on_cancelled_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_instances_on_cancelled_by_id ON public.workflow_instances USING btree (cancelled_by_id);


--
-- Name: index_workflow_instances_on_completed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_instances_on_completed_at ON public.workflow_instances USING btree (completed_at);


--
-- Name: index_workflow_instances_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_instances_on_started_at ON public.workflow_instances USING btree (started_at);


--
-- Name: index_workflow_instances_on_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_instances_on_workflow_id ON public.workflow_instances USING btree (workflow_id);


--
-- Name: index_workflow_steps_on_fallback_assignee_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_on_fallback_assignee_type ON public.workflow_steps USING btree (fallback_assignee_type);


--
-- Name: index_workflow_steps_on_node_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_on_node_type ON public.workflow_steps USING btree (node_type);


--
-- Name: index_workflow_steps_on_workflow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_steps_on_workflow_id ON public.workflow_steps USING btree (workflow_id);


--
-- Name: index_workflow_tasks_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_tasks_on_user_id ON public.workflow_tasks USING btree (user_id);


--
-- Name: index_workflow_tasks_on_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_tasks_on_user_id_and_status ON public.workflow_tasks USING btree (user_id, status);


--
-- Name: index_workflow_tasks_on_workflow_instance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_tasks_on_workflow_instance_id ON public.workflow_tasks USING btree (workflow_instance_id);


--
-- Name: index_workflow_tasks_on_workflow_step_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_tasks_on_workflow_step_id ON public.workflow_tasks USING btree (workflow_step_id);


--
-- Name: audit_logs trigger_protect_audit_logs; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_protect_audit_logs BEFORE DELETE OR UPDATE ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.protect_audit_logs();


--
-- Name: asset_usage_events fk_rails_0293fbe937; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_usage_events
    ADD CONSTRAINT fk_rails_0293fbe937 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_impersonators fk_rails_0e3899ff7f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_impersonators
    ADD CONSTRAINT fk_rails_0e3899ff7f FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: metadata_imports fk_rails_15b95b9093; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_imports
    ADD CONSTRAINT fk_rails_15b95b9093 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_batch_jobs fk_rails_15c9fd11b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_batch_jobs
    ADD CONSTRAINT fk_rails_15c9fd11b5 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: workflow_tasks fk_rails_1c88744c14; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_tasks
    ADD CONSTRAINT fk_rails_1c88744c14 FOREIGN KEY (workflow_instance_id) REFERENCES public.workflow_instances(id);


--
-- Name: workflow_tasks fk_rails_1e3aeeeb80; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_tasks
    ADD CONSTRAINT fk_rails_1e3aeeeb80 FOREIGN KEY (workflow_step_id) REFERENCES public.workflow_steps(id);


--
-- Name: audit_logs fk_rails_1f26bc34ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT fk_rails_1f26bc34ae FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: video_encoding_presets fk_rails_21716e2d82; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_encoding_presets
    ADD CONSTRAINT fk_rails_21716e2d82 FOREIGN KEY (video_profile_id) REFERENCES public.video_profiles(id);


--
-- Name: renditions fk_rails_27f1b0206e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renditions
    ADD CONSTRAINT fk_rails_27f1b0206e FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: folders fk_rails_2a04d378cf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folders
    ADD CONSTRAINT fk_rails_2a04d378cf FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ingestion_items fk_rails_2ff68eeae6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_items
    ADD CONSTRAINT fk_rails_2ff68eeae6 FOREIGN KEY (ingestion_batch_id) REFERENCES public.ingestion_batches(id);


--
-- Name: agent_workflows fk_rails_37b86b2d50; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_workflows
    ADD CONSTRAINT fk_rails_37b86b2d50 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: assets fk_rails_38137d4693; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_38137d4693 FOREIGN KEY (active_version_id) REFERENCES public.asset_versions(id);


--
-- Name: user_group_memberships fk_rails_42022c51df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_group_memberships
    ADD CONSTRAINT fk_rails_42022c51df FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: collection_assets fk_rails_42b7984282; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_assets
    ADD CONSTRAINT fk_rails_42b7984282 FOREIGN KEY (collection_id) REFERENCES public.collections(id);


--
-- Name: asset_usage_events fk_rails_4484bf5a65; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_usage_events
    ADD CONSTRAINT fk_rails_4484bf5a65 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: collection_rules fk_rails_4cb8ce7ec8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_rules
    ADD CONSTRAINT fk_rails_4cb8ce7ec8 FOREIGN KEY (collection_id) REFERENCES public.collections(id);


--
-- Name: style_presets fk_rails_4e83ef4429; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.style_presets
    ADD CONSTRAINT fk_rails_4e83ef4429 FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: inbox_messages fk_rails_5468752965; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_messages
    ADD CONSTRAINT fk_rails_5468752965 FOREIGN KEY (recipient_id) REFERENCES public.users(id);


--
-- Name: folders fk_rails_58e285f76e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folders
    ADD CONSTRAINT fk_rails_58e285f76e FOREIGN KEY (parent_id) REFERENCES public.folders(id);


--
-- Name: assets fk_rails_590236dc2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_590236dc2e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: image_profile_folder_assignments fk_rails_59f3e1753d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_profile_folder_assignments
    ADD CONSTRAINT fk_rails_59f3e1753d FOREIGN KEY (image_profile_id) REFERENCES public.image_profiles(id);


--
-- Name: metadata_exports fk_rails_5c24c02805; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_exports
    ADD CONSTRAINT fk_rails_5c24c02805 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: renditions fk_rails_5cbb791ced; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.renditions
    ADD CONSTRAINT fk_rails_5cbb791ced FOREIGN KEY (storage_backend_id) REFERENCES public.storage_backends(id);


--
-- Name: asset_embeddings fk_rails_606b8a4353; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_embeddings
    ADD CONSTRAINT fk_rails_606b8a4353 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: metadata_schemas fk_rails_60ab5095ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schemas
    ADD CONSTRAINT fk_rails_60ab5095ed FOREIGN KEY (parent_id) REFERENCES public.metadata_schemas(id);


--
-- Name: collection_assets fk_rails_62a239ce45; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_assets
    ADD CONSTRAINT fk_rails_62a239ce45 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: quarantined_assets fk_rails_70a650ffc7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quarantined_assets
    ADD CONSTRAINT fk_rails_70a650ffc7 FOREIGN KEY (system_connector_id) REFERENCES public.system_connectors(id);


--
-- Name: report_snapshots fk_rails_724b217b86; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_snapshots
    ADD CONSTRAINT fk_rails_724b217b86 FOREIGN KEY (report_definition_id) REFERENCES public.report_definitions(id);


--
-- Name: video_profile_folder_assignments fk_rails_72f5d4069f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.video_profile_folder_assignments
    ADD CONSTRAINT fk_rails_72f5d4069f FOREIGN KEY (video_profile_id) REFERENCES public.video_profiles(id);


--
-- Name: oauth_access_tokens fk_rails_732cb83ab7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_tokens
    ADD CONSTRAINT fk_rails_732cb83ab7 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: collection_assets fk_rails_7e990c13ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collection_assets
    ADD CONSTRAINT fk_rails_7e990c13ef FOREIGN KEY (collection_rule_id) REFERENCES public.collection_rules(id);


--
-- Name: asset_provenance_records fk_rails_866ef11ca9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_provenance_records
    ADD CONSTRAINT fk_rails_866ef11ca9 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: asset_versions fk_rails_8bf75f0f47; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_versions
    ADD CONSTRAINT fk_rails_8bf75f0f47 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: inbox_messages fk_rails_8f2db431c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_messages
    ADD CONSTRAINT fk_rails_8f2db431c6 FOREIGN KEY (email_template_id) REFERENCES public.email_templates(id);


--
-- Name: duplicate_group_assets fk_rails_8f767faa5d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_group_assets
    ADD CONSTRAINT fk_rails_8f767faa5d FOREIGN KEY (duplicate_group_id) REFERENCES public.duplicate_groups(id);


--
-- Name: folder_policies fk_rails_957633ec2f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_policies
    ADD CONSTRAINT fk_rails_957633ec2f FOREIGN KEY (folder_id) REFERENCES public.folders(id);


--
-- Name: custom_node_definitions fk_rails_982551730a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.custom_node_definitions
    ADD CONSTRAINT fk_rails_982551730a FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: agent_executions fk_rails_984da1e238; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_executions
    ADD CONSTRAINT fk_rails_984da1e238 FOREIGN KEY (agent_workflow_id) REFERENCES public.agent_workflows(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: inbox_messages fk_rails_9d8e3b1b39; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbox_messages
    ADD CONSTRAINT fk_rails_9d8e3b1b39 FOREIGN KEY (sender_id) REFERENCES public.users(id);


--
-- Name: metadata_schemas fk_rails_9db3b2ddcc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schemas
    ADD CONSTRAINT fk_rails_9db3b2ddcc FOREIGN KEY (inherits_from_id) REFERENCES public.metadata_schemas(id);


--
-- Name: asset_versions fk_rails_9eaf8318f3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_versions
    ADD CONSTRAINT fk_rails_9eaf8318f3 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: ingestion_batches fk_rails_a51efdc248; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ingestion_batches
    ADD CONSTRAINT fk_rails_a51efdc248 FOREIGN KEY (connector_id) REFERENCES public.system_connectors(id) ON DELETE SET NULL;


--
-- Name: workflow_tasks fk_rails_a54e91259b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_tasks
    ADD CONSTRAINT fk_rails_a54e91259b FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: in_app_notifications fk_rails_a5f2d7e793; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.in_app_notifications
    ADD CONSTRAINT fk_rails_a5f2d7e793 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_preferences fk_rails_a69bfcfd81; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preferences
    ADD CONSTRAINT fk_rails_a69bfcfd81 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_group_memberships fk_rails_aece7151f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_group_memberships
    ADD CONSTRAINT fk_rails_aece7151f8 FOREIGN KEY (user_group_id) REFERENCES public.user_groups(id);


--
-- Name: workflow_steps fk_rails_af7ad8555a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_steps
    ADD CONSTRAINT fk_rails_af7ad8555a FOREIGN KEY (workflow_id) REFERENCES public.workflows(id);


--
-- Name: notifications fk_rails_b080fb4855; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_b080fb4855 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: quarantined_assets fk_rails_b333fb5988; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quarantined_assets
    ADD CONSTRAINT fk_rails_b333fb5988 FOREIGN KEY (reviewed_by_id) REFERENCES public.users(id);


--
-- Name: email_deliveries fk_rails_b387ef50cc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_deliveries
    ADD CONSTRAINT fk_rails_b387ef50cc FOREIGN KEY (email_template_id) REFERENCES public.email_templates(id);


--
-- Name: oauth_access_grants fk_rails_b4b53e07b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oauth_access_grants
    ADD CONSTRAINT fk_rails_b4b53e07b8 FOREIGN KEY (application_id) REFERENCES public.oauth_applications(id);


--
-- Name: workflow_instances fk_rails_b82a522ef9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT fk_rails_b82a522ef9 FOREIGN KEY (workflow_id) REFERENCES public.workflows(id);


--
-- Name: folder_policies fk_rails_b8bd408b5a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.folder_policies
    ADD CONSTRAINT fk_rails_b8bd408b5a FOREIGN KEY (user_group_id) REFERENCES public.user_groups(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: user_impersonators fk_rails_c687e0dbf3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_impersonators
    ADD CONSTRAINT fk_rails_c687e0dbf3 FOREIGN KEY (impersonator_id) REFERENCES public.users(id);


--
-- Name: in_app_notifications fk_rails_c6dfe92717; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.in_app_notifications
    ADD CONSTRAINT fk_rails_c6dfe92717 FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: metadata_schema_folder_assignments fk_rails_cfd48135c7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metadata_schema_folder_assignments
    ADD CONSTRAINT fk_rails_cfd48135c7 FOREIGN KEY (metadata_schema_id) REFERENCES public.metadata_schemas(id);


--
-- Name: duplicate_groups fk_rails_cfef2178f1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_groups
    ADD CONSTRAINT fk_rails_cfef2178f1 FOREIGN KEY (resolved_by_id) REFERENCES public.users(id);


--
-- Name: workflow_instances fk_rails_d0b58f56c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT fk_rails_d0b58f56c4 FOREIGN KEY (cancelled_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: quarantined_assets fk_rails_d4a6a4f170; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quarantined_assets
    ADD CONSTRAINT fk_rails_d4a6a4f170 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: user_groups fk_rails_da7f4bdaa5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_groups
    ADD CONSTRAINT fk_rails_da7f4bdaa5 FOREIGN KEY (parent_id) REFERENCES public.user_groups(id);


--
-- Name: assets fk_rails_e0424c2c3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_e0424c2c3e FOREIGN KEY (folder_id) REFERENCES public.folders(id);


--
-- Name: duplicate_group_assets fk_rails_e5995b56ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.duplicate_group_assets
    ADD CONSTRAINT fk_rails_e5995b56ce FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: workflow_instances fk_rails_e9c5284d03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_instances
    ADD CONSTRAINT fk_rails_e9c5284d03 FOREIGN KEY (asset_id) REFERENCES public.assets(id);


--
-- Name: email_templates fk_rails_ed5fa5637b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT fk_rails_ed5fa5637b FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260710120000'),
('20260709163140'),
('20260709160000'),
('20260709150000'),
('20260709140000'),
('20260709130000'),
('20260709112600'),
('20260709095000'),
('20260707150001'),
('20260707150000'),
('20260705170000'),
('20260703120000'),
('20260702120000'),
('20260701120001'),
('20260701120000'),
('20260629120000'),
('20260628200001'),
('20260628140001'),
('20260628130001'),
('20260628120001'),
('20260628120000'),
('20260628110000'),
('20260628100000'),
('20260626130000'),
('20260626092131'),
('20260626000003'),
('20260626000002'),
('20260626000001'),
('20260625100001'),
('20260625000004'),
('20260625000003'),
('20260625000002'),
('20260625000001'),
('20260624200001'),
('20260624100003'),
('20260624100002'),
('20260624100001'),
('20260624000002'),
('20260624000001'),
('20260623130000'),
('20260623120000'),
('20260623000002'),
('20260623000001'),
('20260622000001'),
('20260616165408'),
('20260611155813'),
('20260610100804'),
('20260608150535'),
('20260608150534'),
('20260608131110'),
('20260603160008'),
('20260603154231'),
('20260603150235'),
('20260603140755'),
('20260603084017'),
('20260603052143'),
('20260603052129'),
('20260602134823'),
('20260602134754'),
('20260602092755'),
('20260527164224'),
('20260527164214'),
('20260527145918'),
('20260527142102'),
('20260527140226'),
('20260527134651'),
('20260527110255'),
('20260526121213'),
('20260526113050'),
('20260526112354'),
('20260521150607'),
('20260521093920'),
('20260521093843'),
('20260521093801'),
('20260521073107'),
('20260520075119'),
('20260520075019'),
('20260519124426'),
('20260519123458'),
('20260519123443'),
('20260519123431'),
('20260519074955'),
('20260513122403'),
('20260513115128'),
('20260513114939'),
('20260513113310'),
('20260513113304'),
('20260513095132'),
('20260513095125'),
('20260513095117'),
('20260507150008'),
('20260507114127'),
('20260507111925'),
('20260507090858'),
('20260424141528'),
('20260424095038'),
('20260424094921'),
('20260424094852'),
('20260424063532'),
('20260424063350'),
('20260424063331'),
('20260423104154');

