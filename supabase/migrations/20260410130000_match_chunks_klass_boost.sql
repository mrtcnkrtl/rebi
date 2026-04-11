-- Optional klass topic boost for vector search: prefer chunks whose klass.topic matches query hints;
-- unclassified or missing topic rank before mismatched topic. Same limit, no extra rows.

create or replace function public.match_knowledge_chunks(
  p_user_id uuid,
  p_query_embedding vector(768),
  p_match_count int default 8,
  p_folder_id uuid default null,
  p_klass_topics text[] default null
)
returns table (
  chunk_id uuid,
  document_id uuid,
  chunk_text text,
  similarity float
)
language sql
stable
as $$
  select
    c.id as chunk_id,
    c.document_id,
    c.chunk_text,
    (1 - (c.embedding <=> p_query_embedding))::float as similarity
  from public.knowledge_chunks c
  where c.user_id = p_user_id
    and c.embed_ok is true
    and c.embedding is not null
    and (p_folder_id is null or c.folder_id = p_folder_id)
  order by
    (
      case
        when p_klass_topics is null or cardinality(p_klass_topics) = 0 then 0
        when c.klass ? 'topic' and (c.klass->>'topic' = any(p_klass_topics)) then 0
        when c.klass = '{}'::jsonb or not (c.klass ? 'topic') then 1
        else 2
      end
    ),
    c.embedding <=> p_query_embedding
  limit greatest(p_match_count, 1);
$$;
