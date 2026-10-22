#!/usr/bin/env python3
"""Build the project overview from the registered operational event catalog."""

import json
import subprocess
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'grafana/dashboards/operational.json'
DS = {'type': 'prometheus', 'uid': '${DS_PROMETHEUS}'}
SCOPE = 'job="$job", instance="$instance"'
HTTP = 'bolognesa_prom_ex_phoenix_http_request_duration_milliseconds'
ECTO = 'bolognesa_prom_ex_ecto_repo_query_execution_time_milliseconds'
LV = 'bolognesa_prom_ex_phoenix_live_view'
OBAN = 'bolognesa_prom_ex_oban'
BEAM = 'bolognesa_prom_ex_beam'
CONTEXTS = ('accounts', 'libraries', 'movies', 'series', 'music', 'playback')
SOURCES = {
    'accounts': 'accounts_.+', 'libraries': 'libraries|library_scans|media_files|media_inspections',
    'movies': 'movies|movie_identifications',
    'series': 'series|seasons|episodes|series_identifications|series_identification_episodes',
    'music': 'music_.+',
}
# These match exported route templates, never concrete URLs or identifiers.
PATHS = {
    'accounts': '/setup|/login|/logout|/settings', 'libraries': '/libraries',
    'movies': '/movies|/movies/review|/movies/:id',
    'series': '/series|/series/review|/series/:id|/series/seasons/:id|/episodes/:id',
    'music': '/music', 'playback': '/(movies|episodes|music/tracks)/.+/media/.+',
}
WORKERS = {'libraries': 'Libraries', 'movies': 'Movies', 'series': 'Series', 'music': 'Music'}
LATENCY_NOTE = ('Mean is measured total / samples; p50/p95 are histogram estimates. '
                'With few samples they can coincide. No duration samples means no data. '
                'Percentiles cannot recover individual operation durations.')
COUNT_NOTE = ('Estimated increase over the selected range; Prometheus extrapolates and may show '
              'fractions or miss events before the first scrape. No data is not zero. '
              'Starts, outcomes and retries are separate observations, not unique operations.')


def selector(metric, extra=''):
    return f'{metric}{{{SCOPE}{", " + extra if extra else ""}}}'


def increase(metric, extra='', window='$__range', group=''):
    by = f' by ({group})' if group else ''
    return f'sum{by}(increase({selector(metric, extra)}[{window}]))'


def latency(metric, extra='', window='$window'):
    count = increase(metric + '_count', extra, window)
    mean = f'{increase(metric + "_sum", extra, window)} / ({count} > 0)'
    return [(mean, 'Mean')] + [
        (f'histogram_quantile({q}, {increase(metric + "_bucket", extra, window, "le")})', label)
        for q, label in [(0.5, 'p50'), (0.95, 'p95')]
    ]


class Dashboard:
    def __init__(self):
        self.panels = []
        self.y = 0
        self.x = 0
        self.height = 0

    def next_line(self):
        self.y += self.height
        self.x = self.height = 0

    def row(self, title):
        self.next_line()
        self.panels.append({'id': len(self.panels) + 1, 'type': 'row', 'title': title,
                            'collapsed': False, 'panels': [],
                            'gridPos': {'x': 0, 'y': self.y, 'w': 24, 'h': 1}})
        self.y += 1

    def panel(self, title, queries, unit='short', kind='timeseries', width=8, description='', height=None):
        if self.x + width > 24:
            self.next_line()
        height = height or (5 if kind == 'stat' else 8)
        defaults = {'unit': unit, 'noValue': 'No data', 'color': {'mode': 'palette-classic'}}
        if kind == 'timeseries':
            defaults['custom'] = {'drawStyle': 'line', 'lineWidth': 1, 'fillOpacity': 8,
                                  'showPoints': 'auto', 'spanNulls': False}
        overrides = []
        for outcome, color in [('failed', 'red'), ('retryable', 'orange'), ('degraded', 'orange'),
                               ('completed', 'green'), ('rejected', 'yellow'), ('stale', 'blue')]:
            overrides.append({'matcher': {'id': 'byRegexp', 'options': f'.*{outcome}.*'},
                              'properties': [{'id': 'color', 'value': {'mode': 'fixed', 'fixedColor': color}}]})
        options = ({'reduceOptions': {'calcs': ['lastNotNull'], 'fields': '', 'values': False},
                    'colorMode': 'none', 'graphMode': 'none', 'textMode': 'auto',
                    'orientation': 'auto', 'justifyMode': 'auto'} if kind == 'stat' else
                   {'legend': {'displayMode': 'table', 'placement': 'bottom', 'calcs': ['lastNotNull']},
                    'tooltip': {'mode': 'multi', 'sort': 'desc'}})
        self.panels.append({
            'id': len(self.panels) + 1, 'type': kind, 'title': title, 'description': description,
            'datasource': DS, 'gridPos': {'x': self.x, 'y': self.y, 'w': width, 'h': height},
            'fieldConfig': {'defaults': defaults, 'overrides': overrides}, 'options': options,
            'targets': [{'refId': f'Q{i}', 'expr': expr, 'legendFormat': label,
                         'editorMode': 'code', 'instant': kind == 'stat', 'range': kind != 'stat'}
                        for i, (expr, label) in enumerate(queries)],
        })
        self.x += width
        self.height = max(self.height, height)

    def timings(self, title, metric, extra='', description=''):
        self.panel(title, latency(metric, extra), 'ms', description=description + ' ' + LATENCY_NOTE)


def catalog():
    code = ('events = Bolognesa.Infrastructure.Observability.Events.events() ++ '
            'Bolognesa.Infrastructure.Observability.PlaybackEvents.events(); '
            'IO.puts("EVENTS:" <> Jason.encode!(events))')
    result = subprocess.run(['mix', 'run', '--no-start', '-e', code], cwd=ROOT,
                            check=True, capture_output=True, text=True)
    return json.loads(next(line[7:] for line in result.stdout.splitlines() if line.startswith('EVENTS:')))


def build(events):
    base = json.loads((ROOT / 'grafana/dashboards/operational.json').read_text())
    d = Dashboard()
    d.row('Overview')
    d.panel('Application scrape', [(f'up{{{SCOPE}}}', 'Scrape')], kind='stat', width=6,
            description='1 = scrape succeeded; 0 = scrape failed. Missing data can mean collector or delivery failure. Not a business health check.')
    d.panel('HTTP requests · selected range', [(increase('bolognesa_prom_ex_phoenix_http_requests_total'), 'Requests')],
            kind='stat', width=6, description=COUNT_NOTE)
    d.panel('HTTP server errors · selected range', [(increase('bolognesa_prom_ex_phoenix_http_requests_total', 'status=~"5.."'), '5xx')],
            kind='stat', width=6, description=COUNT_NOTE)
    d.panel('Jobs awaiting work / executing', [(f'sum by (state) ({selector(OBAN + "_queue_length_count", "state=~\"available|scheduled|retryable|executing\"")})', '{{state}}')],
            kind='stat', width=6, description='Current persisted queue state, polled every 60 seconds. Not a count over the selected range.')
    d.timings('HTTP response duration', HTTP)
    d.panel('Operational problems · rolling window', [
        (increase('_'.join(e) + '_count', window='$window'), '.'.join(e[1:]))
        for e in events if e[-1] in ('failed', 'retryable', 'degraded')],
        description=COUNT_NOTE + ' Window: $window. Failures, retries and degradation remain separate.')
    d.panel('HTTP responses · rolling window', [(increase('bolognesa_prom_ex_phoenix_http_requests_total', window='$window', group='status'), '{{status}}')], description=COUNT_NOTE)

    resources = defaultdict(list)
    for event in events:
        resources[(event[1], event[2])].append(event)
    for context in CONTEXTS:
        d.row(context.title())
        for (owner, resource), members in resources.items():
            if owner != context:
                continue
            d.next_line()
            title = resource.replace('_', ' ').title()
            timed = (resource in ('scan', 'inspection', 'identification', 'correction', 'import', 'reconciliation')
                     or (context == 'playback' and resource == 'session'))
            outcomes = [(increase('_'.join(e) + '_count'), e[-1]) for e in sorted(members)]
            if timed:
                outcomes.append((increase('', f'__name__=~"bolognesa_{context}_{resource}_.+_duration_milliseconds_count"', '$window'), 'Duration samples · $window'))
            d.panel(f'{title} · outcomes in selected range', outcomes,
                    kind='stat', width=6, height=8,
                    description=COUNT_NOTE + ' Duration samples use the same rolling window as the latency panel.')
            d.panel(f'{title} · activity per $window',
                    [(increase('_'.join(e) + '_count', window='$window'), e[-1]) for e in sorted(members)],
                    width=9 if timed else 18, description=COUNT_NOTE)
            if timed:
                expressions = []
                for suffix in ('_sum', '_count'):
                    pattern = f'bolognesa_{context}_{resource}_.+_duration_milliseconds{suffix}'
                    expressions.append(increase('', f'__name__=~"{pattern}"', '$window'))
                buckets = increase('', f'__name__=~"bolognesa_{context}_{resource}_.+_duration_milliseconds_bucket"', '$window', 'le')
                d.panel(f'{title} · duration', [(f'{expressions[0]} / ({expressions[1]} > 0)', 'Mean')] +
                        [(f'histogram_quantile({q}, {buckets})', label) for q, label in [(0.5, 'p50'), (0.95, 'p95')]], 'ms', width=9,
                        description=LATENCY_NOTE + (' Session lifetime until close; not startup latency.' if resource == 'session' else ' Measured outcomes combined; starts without a duration do not contribute.'))
        if context == 'playback':
            for title, metric, label in [
                ('Browser · buffer waits, recovery and errors', 'bolognesa_playback_browser_observations_total', 'diagnostic'),
                ('FFmpeg · exit results', 'bolognesa_playback_ffmpeg_exits_total', 'result'),
                ('Sessions · close reasons', 'bolognesa_playback_session_closures_total', 'reason'),
            ]:
                d.panel(title, [(increase(metric, window='$window', group=label), '{{' + label + '}}')],
                        description='Bounded diagnostic observations. Browser reporting is best effort and capped at 120 observations per LiveView lifetime; not all playback failures reach the server. ' + COUNT_NOTE)
        d.next_line()
        path = f'path=~"{PATHS[context]}"'
        d.panel('HTTP · requests by route and status', [(increase('bolognesa_prom_ex_phoenix_http_requests_total', path, '$window', 'path, status'), '{{path}} · {{status}}')],
                description='HTTP requests only; LiveView interactions after mount use the WebSocket. Media routes belong to Playback. ' + COUNT_NOTE)
        d.timings('HTTP · response duration', HTTP, path)
        if context != 'playback':
            live_filter = f'context="{context}"'
            d.panel('LiveView · callbacks and exceptions', [
                (increase(f'{LV}_{op}{error}_duration_milliseconds_count', live_filter, '$window'), f'{op}{error}')
                for op in ('mount', 'handle_params', 'handle_event', 'render') for error in ('', '_exception')],
                description='Callback observations, not connected users or completed workflows. ' + COUNT_NOTE)
            d.timings('LiveView · event handling duration', LV + '_handle_event_duration_milliseconds', live_filter)
            d.timings('Ecto · owned source execution', ECTO, f'source=~"{SOURCES[context]}"',
                      'Attribution is by the primary table reported by Ecto, not the caller or every table in a join.')
            d.panel('Ecto · query errors by owned source', [(increase('bolognesa_prom_ex_ecto_repo_query_errors_total', f'source=~"{SOURCES[context]}"', '$window', 'source'), '{{source}}')],
                    description='Ecto query results reported as errors, attributed by primary source. No SQL, parameters or error text are labels. ' + COUNT_NOTE)
        if context in WORKERS:
            worker = f'worker=~"(Elixir\\\\.)?Bolognesa\\\\.{WORKERS[context]}\\\\..+"'
            d.panel('Oban · attempts by worker', [(increase(OBAN + f'_job_{event}_duration_milliseconds_count', worker, '$window', 'worker'), '{{worker}} · ' + event)
                    for event in ('processing', 'exception')], description='Worker ownership; Movies and Series share a queue. Exceptions are attempts, not necessarily terminal failures. ' + COUNT_NOTE)
            d.timings('Oban · processing duration', OBAN + '_job_processing_duration_milliseconds', worker)
            d.timings('Oban · time waiting in queue', OBAN + '_job_queue_time_milliseconds', worker)

    d.row('Phoenix / LiveView · global')
    d.panel('HTTP · responses by status', [(increase('bolognesa_prom_ex_phoenix_http_requests_total', window='$window', group='status'), '{{status}}')], description=COUNT_NOTE)
    d.timings('HTTP · all route durations', HTTP)
    d.panel('LiveView · callback volume', [(increase(f'{LV}_{op}_duration_milliseconds_count', window='$window', group='context'), '{{context}} · ' + op)
            for op in ('mount', 'handle_params', 'handle_event', 'render')], description=COUNT_NOTE)
    d.panel('LiveView · callback exceptions', [(increase(f'{LV}_{op}_exception_duration_milliseconds_count', window='$window', group='context'), '{{context}} · ' + op)
            for op in ('mount', 'handle_params', 'handle_event', 'render')], description='Exceptions only; expected validation and authorization results are not exceptions. ' + COUNT_NOTE)
    for op in ('mount', 'handle_params', 'handle_event', 'render'):
        d.timings(f'LiveView · {op} duration', f'{LV}_{op}_duration_milliseconds')

    d.row('Ecto · global and shared')
    d.panel('Queries · selected range', [(increase(ECTO + '_count'), 'Queries')], kind='stat', description=COUNT_NOTE)
    d.panel('Configured connection pool', [(selector('bolognesa_prom_ex_ecto_repo_init_pool_size'), '{{repo}}')], kind='stat',
            description='Configured pool size, not current connection occupancy.')
    d.panel('Queries by source · per $window', [(increase(ECTO + '_count', window='$window', group='source'), '{{source}}')], description=COUNT_NOTE)
    for component in ('total', 'execution', 'queue', 'decode', 'idle'):
        d.timings(f'Ecto · {component} time', f'bolognesa_prom_ex_ecto_repo_query_{component}_time_milliseconds',
                  description='Idle time measures connection inactivity before checkout, not contention.' if component == 'idle' else '')
    owned_sources = '|'.join(SOURCES.values())
    d.timings('Shared / unclassified source execution', ECTO, f'source!~"{owned_sources}"',
              'Includes Oban tables, transactions and queries without a classified primary source. Playback reads content-owned tables and has no independent persistence table.')
    d.panel('Query errors · per $window', [(increase('bolognesa_prom_ex_ecto_repo_query_errors_total', window='$window', group='source'), '{{source}}')],
            description='Ecto query results reported as errors, including shared and unclassified sources. No SQL or error details are exported. ' + COUNT_NOTE)

    d.row('Oban · global')
    d.panel('Queue state', [(selector(OBAN + '_queue_length_count'), '{{queue}} · {{state}}')], description='Polled database gauges, including retained completed/discarded jobs.')
    d.panel('Queue concurrency', [(selector(OBAN + '_init_queue_concurrency_limit'), '{{queue}}')], kind='stat')
    d.panel('Job exceptions · per $window', [(increase(OBAN + '_job_exception_duration_milliseconds_count', window='$window', group='queue, worker'), '{{queue}} · {{worker}}')], description=COUNT_NOTE)
    d.timings('Job execution duration', OBAN + '_job_processing_duration_milliseconds')
    d.timings('Job queue wait', OBAN + '_job_queue_time_milliseconds')
    d.panel('Circuit breaker events · per $window', [(increase(OBAN + f'_circuit_{event}_total', window='$window'), event) for event in ('trip', 'open')], description=COUNT_NOTE)

    d.row('BEAM · runtime resources')
    d.panel('Uptime', [(selector(BEAM + '_stats_uptime_milliseconds_count'), 'Uptime')], 'ms', 'stat')
    for title, names, unit in [
        ('Memory', ['memory_allocated_bytes', 'memory_processes_total_bytes', 'memory_binary_total_bytes', 'memory_ets_total_bytes', 'memory_atom_total_bytes', 'memory_code_total_bytes'], 'bytes'),
        ('Processes / ports / ETS', ['stats_process_count', 'stats_port_count', 'stats_ets_count'], 'short'),
        ('Scheduler work and run queues', ['stats_active_task_count', 'stats_run_queue_count'], 'short'),
        ('Atoms', ['stats_atom_count', 'system_atom_limit_info'], 'short'),
    ]:
        d.panel(title, [(selector(BEAM + '_' + name), name + ' {{type}}') for name in names], unit)
    for title, name, unit, extra in [
        ('Garbage collections', 'stats_gc_count', 'ops', ''),
        ('GC reclaimed bytes', 'stats_gc_reclaimed_bytes', 'Bps', ''),
        ('Reductions', 'stats_reduction_count', 'ops', ''),
        ('Port I/O', 'stats_port_io_byte_count', 'Bps', ''),
    ]:
        d.panel(title, [(f'rate({selector(BEAM + "_" + name)}[$__rate_interval])', '{{type}}')], unit)

    d.row('Docker · optional Linux collector')
    docker = 'job="bolognesa-docker", instance="$instance"'
    def container(metric):
        return f'{metric}{{{docker}}}'
    d.panel('Docker collector scrape', [(f'up{{{docker}}}', 'Scrape')], kind='stat',
            description='Requires monitoring.docker.yaml on native Linux. No data means absent or unavailable collection, not zero resource use. The exporter may be up even when container discovery fails.')
    d.panel('Containers observed recently', [(f'count by (service) ({container("container_last_seen")} > time() - 180)', '{{service}}')], kind='stat',
            description='At least one fresh container sample per service. Missing service requires investigation; scrape success alone is insufficient.')
    d.panel('CPU · cores used', [(f'sum by (service) (rate({container("container_cpu_usage_seconds_total")}[$__rate_interval]))', '{{service}}')], 'short',
            description='One unit is one CPU core. Includes FFmpeg subprocesses in the app container.')
    d.panel('Memory · working set', [(f'sum by (service) ({container("container_memory_working_set_bytes")})', '{{service}}')], 'bytes')
    d.panel('Memory · configured limit', [(f'max by (service) ({container("container_spec_memory_limit_bytes")})', '{{service}}')], 'bytes',
            description='An unlimited container can report the host memory limit.')
    d.panel('Network · receive / transmit', [(f'sum by (service) (rate({container(metric)}[$__rate_interval]))', '{{service}} · ' + label)
            for metric, label in [('container_network_receive_bytes_total', 'RX'), ('container_network_transmit_bytes_total', 'TX')]], 'Bps',
            description='Per-container network counters. Host-network containers can share host counters; values must not be summed into a host total.')
    d.panel('Block I/O · read / write', [(f'sum by (service) (rate({container(metric)}[$__rate_interval]))', '{{service}} · ' + label)
            for metric, label in [('container_fs_reads_bytes_total', 'read'), ('container_fs_writes_bytes_total', 'write')]], 'Bps',
            description='Block I/O exposed by the runtime; may be absent depending on storage driver. Does not measure media capacity or free space.')
    d.panel('Container starts', [(f'max by (service) ({container("container_start_time_seconds")}) * 1000', '{{service}}')], 'dateTimeAsIso', 'stat',
            description='Most recent container start timestamp. This is not a durable restart counter.')

    # Lazy rows keep the overview usable without issuing every diagnostic query on load.
    panels = []
    active_row = None
    for panel in d.panels:
        if panel['type'] == 'row':
            active_row = panel
            active_row['collapsed'] = panel['title'] != 'Overview'
            panels.append(panel)
        elif active_row and active_row['collapsed']:
            active_row['panels'].append(panel)
        else:
            panels.append(panel)
    base.update(title='Bolognesa · Project overview', description='Context functionality and infrastructure overview for low-traffic home use. Counts are scrape-based estimates; missing data is never healthy zero. Mean, p50 and p95 are paired with sample counts. Rolling activity window is independently selectable.',
                panels=panels, version=3, graphTooltip=1, time={'from': 'now-24h', 'to': 'now'})
    variables = [v for v in base['templating']['list'] if v['name'] in ('job', 'instance')]
    variables.append({'name': 'window', 'label': 'Activity / latency window', 'type': 'custom',
                      'query': '15m,1h,6h,24h', 'current': {'text': '1h', 'value': '1h'},
                      'options': [{'text': v, 'value': v, 'selected': v == '1h'} for v in ('15m', '1h', '6h', '24h')]})
    base['templating']['list'] = variables
    return base


if __name__ == '__main__':
    OUTPUT.write_text(json.dumps(build(catalog()), indent=2) + '\n')
    print(OUTPUT.relative_to(ROOT))
