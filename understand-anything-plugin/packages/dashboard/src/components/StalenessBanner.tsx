import { useState } from "react";
import type {
  DashboardFreshnessReport,
  GraphFreshnessResult,
  GraphFreshnessUnknownReason,
} from "../freshness";
import { useI18n } from "../contexts/I18nContext";
import type { Locale } from "../locales";

interface StalenessBannerProps {
  freshness: DashboardFreshnessReport | null;
}

interface FreshnessBannerContent {
  title: string;
  summary: string;
  action: string;
  changedFiles: string[];
}

type GraphName = "knowledge" | "domain";
type GraphEntry = { name: GraphName; result: GraphFreshnessResult };

const RISK_RANK: Record<GraphFreshnessResult["status"], number> = {
  fresh: 0,
  unknown: 1,
  dirty: 2,
  stale: 3,
};

function graphLabel(name: GraphName, t: Locale): string {
  return name === "knowledge"
    ? t.stalenessBanner.knowledgeGraph
    : t.stalenessBanner.domainGraph;
}

function titleSubject(entries: GraphEntry[], t: Locale): string {
  if (entries.length === 2) return t.stalenessBanner.knowledgeAndDomain;
  return entries[0].name === "knowledge"
    ? t.stalenessBanner.knowledgeGraph
    : t.stalenessBanner.domainGraph;
}

function changedFilesSentence(count: number, t: Locale): string {
  return t.stalenessBanner.fileChanged(count);
}

function staleSummary(entry: GraphEntry, t: Locale): string {
  if (entry.result.status !== "stale") return "";
  const subject = graphLabel(entry.name, t);
  const fileSummary = changedFilesSentence(entry.result.changedFileCount, t);

  if (entry.result.relation === "behind") {
    return t.stalenessBanner.projectCommitBehind(
      subject,
      entry.result.commitsBehind,
      fileSummary,
    );
  }
  if (entry.result.relation === "ahead") {
    return t.stalenessBanner.newerHistory(subject, fileSummary);
  }
  return t.stalenessBanner.differentHistory(subject, fileSummary);
}

function dirtySummary(entry: GraphEntry, t: Locale): string {
  if (entry.result.status !== "dirty") return "";
  return t.stalenessBanner.dirtyFiles(
    graphLabel(entry.name, t),
    entry.result.changedFileCount,
  );
}

function unknownEntrySummary(entry: GraphEntry, t: Locale): string {
  if (entry.result.status !== "unknown") return "";
  if (entry.result.reason === "freshness-request-failed") {
    return t.stalenessBanner.refreshFailed;
  }
  const reasonMap: Record<GraphFreshnessUnknownReason, string> = {
    "missing-graph-commit": t.stalenessBanner.missingGraphCommit,
    "git-head-unavailable": t.stalenessBanner.gitHeadUnavailable,
    "graph-commit-unavailable": t.stalenessBanner.graphCommitUnavailable,
    "git-command-timeout": t.stalenessBanner.gitCommandTimeout,
    "freshness-request-failed": t.stalenessBanner.freshnessRequestFailed,
  };
  return t.stalenessBanner.unknownGraph(
    graphLabel(entry.name, t),
    reasonMap[entry.result.reason],
  );
}

function refreshAction(entries: GraphEntry[], t: Locale): string {
  const hasKnowledge = entries.some((entry) => entry.name === "knowledge");
  const hasDomain = entries.some((entry) => entry.name === "domain");
  const commands = hasKnowledge && hasDomain
    ? "/understand and /understand-domain"
    : hasDomain
      ? "/understand-domain"
      : "/understand";
  return t.stalenessBanner.runRefresh(commands, entries.length !== 1);
}

export function buildFreshnessBanner(
  freshness: DashboardFreshnessReport | null,
  t: Locale,
): FreshnessBannerContent | null {
  if (!freshness) return null;
  const entries: GraphEntry[] = [
    { name: "knowledge", result: freshness.graphs.knowledge },
  ];
  if (freshness.graphs.domain) {
    entries.push({ name: "domain", result: freshness.graphs.domain });
  }

  const highestRisk = Math.max(
    ...entries.map((entry) => RISK_RANK[entry.result.status]),
  );
  if (highestRisk === RISK_RANK.fresh) return null;

  const affected = entries.filter(
    (entry) => RISK_RANK[entry.result.status] === highestRisk,
  );
  const status = affected[0].result.status;
  const changedFiles = [
    ...new Set(
      affected.flatMap((entry) =>
        "changedFiles" in entry.result ? entry.result.changedFiles : [],
      ),
    ),
  ].sort();

  if (status === "stale") {
    return {
      title: `${titleSubject(affected, t)}${t.stalenessBanner.mayBeStale}`,
      summary: affected.map((entry) => staleSummary(entry, t)).join(" "),
      action: refreshAction(affected, t),
      changedFiles,
    };
  }

  if (status === "dirty") {
    return {
      title: `${titleSubject(affected, t)}${
        affected.length === 1
          ? t.stalenessBanner.hasWorkingTreeChanges
          : t.stalenessBanner.haveWorkingTreeChanges
      }`,
      summary: affected.map((entry) => dirtySummary(entry, t)).join(" "),
      action: refreshAction(affected, t),
      changedFiles,
    };
  }

  const requestFailed = affected.some(
    (entry) =>
      entry.result.status === "unknown" &&
      entry.result.reason === "freshness-request-failed",
  );

  return {
    title: `${titleSubject(affected, t)}${t.stalenessBanner.freshnessCouldNotBeVerified}`,
    summary: [...new Set(affected.map((entry) => unknownEntrySummary(entry, t)))].join(" "),
    action: requestFailed
      ? t.stalenessBanner.retryAction
      : refreshAction(affected, t),
    changedFiles: [],
  };
}

export default function StalenessBanner({ freshness }: StalenessBannerProps) {
  const { t } = useI18n();
  const [expanded, setExpanded] = useState(false);
  const content = buildFreshnessBanner(freshness, t);

  if (!content) return null;

  const hasFiles = content.changedFiles.length > 0;
  const visibleFiles = content.changedFiles.slice(0, 8);
  const hiddenFileCount = content.changedFiles.length - visibleFiles.length;

  return (
    <div className="bg-amber-950/30 border-b border-amber-700 text-amber-100 text-sm">
      <button
        type="button"
        aria-expanded={expanded}
        onClick={() => setExpanded((prev) => !prev)}
        className="w-full flex items-start gap-3 px-5 py-3 text-left hover:bg-amber-900/10 transition-colors"
      >
        <svg
          className="w-4 h-4 shrink-0 mt-0.5 text-amber-400"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M12 9v2m0 4h.01M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"
          />
        </svg>
        <span className="flex-1 min-w-0">
          <span className="block font-semibold">{content.title}</span>
          <span className="block text-amber-100/80">{content.summary}</span>
          <span className="block text-amber-100/70">{content.action}</span>
        </span>
        {hasFiles && (
          <span className="text-xs text-amber-300/70 shrink-0">
            {expanded ? t.stalenessBanner.hideFiles : t.stalenessBanner.showFiles}
          </span>
        )}
      </button>

      {expanded && hasFiles && (
        <div className="px-5 pb-3">
          <div className="border-t border-amber-700/40 pt-2 flex flex-wrap gap-1.5">
            {visibleFiles.map((file) => (
              <code
                key={file}
                className="px-1.5 py-0.5 rounded bg-amber-900/30 text-[11px] text-amber-100"
              >
                {file}
              </code>
            ))}
            {hiddenFileCount > 0 && (
              <span className="text-xs text-amber-200/60">
                {t.stalenessBanner.more(hiddenFileCount)}
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
