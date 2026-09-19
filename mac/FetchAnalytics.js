// Runs only inside the account's note.com tab. Credentials never leave Chrome.
async function fetchNoteAnalytics(period, fetchImpl = fetch) {
  const fail = (code) => ({ok: false, code});
  if (location.origin !== 'https://note.com') return fail('loginRequired');
  if (!['LAST_7_DAYS', 'LAST_28_DAYS', 'LAST_365_DAYS', 'ALL'].includes(period)) return fail('invalidPeriod');
  const cookie = (name) => {
    const value = document.cookie.split('; ').find(v => v.startsWith(name + '='));
    return value ? decodeURIComponent(value.slice(name.length + 1)) : null;
  };
  try {
    let token = cookie('note_gql_auth_token');
    async function authenticate() {
      const xsrf = cookie('XSRF-TOKEN');
      const response = await fetchImpl('https://note.com/api/v3/graphql/auth', {
        method: 'POST', credentials: 'include',
        headers: {'x-requested-with': 'XMLHttpRequest', ...(xsrf ? {'x-xsrf-token': xsrf} : {})},
        signal: AbortSignal.timeout(15000)
      });
      if (!response.ok) throw new Error([401,403].includes(response.status) ? 'loginRequired' : 'network');
      token = cookie('note_gql_auth_token');
      if (!token) throw new Error('loginRequired');
    }
    if (!token) await authenticate();
    async function query(queryText, variables, retry = true) {
      const response = await fetchImpl('https://graphql.note.com/graphql', {
        method: 'POST', headers: {'content-type': 'application/json', Authorization: `Bearer ${token}`},
        body: JSON.stringify({query: queryText, variables}), signal: AbortSignal.timeout(15000)
      });
      if ([401,403].includes(response.status)) {
        if (retry) { await authenticate(); return query(queryText, variables, false); }
        throw new Error('loginRequired');
      }
      if (!response.ok) throw new Error('network');
      const json = await response.json();
      if (json.errors?.length) {
        const unauth = json.errors.some(e => /unauthenticated|unauthorized/i.test(e.message));
        if (unauth && retry) { await authenticate(); return query(queryText, variables, false); }
        throw new Error(unauth ? 'loginRequired' : 'schemaChanged');
      }
      if (!json.data) throw new Error('schemaChanged');
      return json.data;
    }
    const now = new Date();
    const date = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,'0')}-${String(now.getDate()).padStart(2,'0')}`;
    const variables = {unit: period, date};
    const fields = 'impressionCount pageViewCount likeCount commentCount';
    const summaryData = await query(`query SwitcherSummary($unit: DashboardPeriodUnit!, $date: Datetime!) {
      dashboardSummary(unit: $unit, date: $date) { lastUpdatedAt metrics { ${fields} } }
    }`, variables);
    const metrics = (m) => {
      if (!m || !['pageViewCount','likeCount','commentCount'].every(k => Number.isSafeInteger(m[k]) && m[k] >= 0)
        || !(m.impressionCount === null || (Number.isSafeInteger(m.impressionCount) && m.impressionCount >= 0))) throw new Error('schemaChanged');
      return {impressions:m.impressionCount, pv:m.pageViewCount, likes:m.likeCount, comments:m.commentCount};
    };
    const summary = summaryData.dashboardSummary;
    const totals = metrics(summary?.metrics);
    const articles = [], seen = new Set(), cursors = new Set();
    let after = null;
    for (let page = 0; page < 100; page++) {
      const data = await query(`query SwitcherArticles($unit: DashboardPeriodUnit!, $date: Datetime!, $after: String) {
        dashboardNoteListConnection(unit: $unit, date: $date, first: 100, after: $after) {
          pageInfo { hasNextPage endCursor }
          edges { node { id note { title publishedAt link { absoluteUrl } } metrics { ${fields} } } }
        }
      }`, {...variables, after});
      const connection = data.dashboardNoteListConnection;
      if (!connection || !Array.isArray(connection.edges) || typeof connection.pageInfo?.hasNextPage !== 'boolean') throw new Error('schemaChanged');
      for (const {node} of connection.edges) {
        if (!node || typeof node.id !== 'string' || !node.note || typeof node.note.title !== 'string') throw new Error('schemaChanged');
        if (seen.has(node.id)) continue;
        seen.add(node.id);
        articles.push({id:node.id, title:node.note.title, publishedAt:node.note.publishedAt ?? null,
          url:node.note.link?.absoluteUrl ?? null, metrics:metrics(node.metrics)});
      }
      if (!connection.pageInfo.hasNextPage) return {ok:true, snapshot:{period, date,
        fetchedAt:new Date().toISOString(), sourceUpdatedAt:summary.lastUpdatedAt ?? null, totals, articles}};
      after = connection.pageInfo.endCursor;
      if (!after || cursors.has(after)) throw new Error('schemaChanged');
      cursors.add(after);
    }
    return fail('tooManyArticles');
  } catch (error) {
    return fail(['loginRequired','schemaChanged','tooManyArticles'].includes(error.message) ? error.message : 'network');
  }
}
