import { useEffect, useMemo, useRef, useState } from 'react';
import {
    compareRegion,
    createImageCache,
    expandRegion,
    isCanvasSecurityError,
    regionDataUrl,
} from '../../utils/regionDiff';

/**
 * Decides, per thread, whether the region it points at actually changed
 * between the version the feedback was written against and the version the
 * reviewer is looking at now.
 *
 * WHY THIS IS WORTH DOING
 * -----------------------
 * A comment thread outlives the version it was written on (see
 * CommentThread). That is what makes "is this still outstanding?" answerable
 * at all — but a human still has to answer it by flipping between two files.
 * Since the annotation geometry is normalised, the same region can be located
 * on both versions and compared directly, so the panel can say "changed in v3"
 * without anyone opening a compare view.
 *
 * WHAT IT DELIBERATELY DOES NOT CLAIM
 * -----------------------------------
 * "Changed" is not "fixed". Pixels moving inside the box is evidence that
 * someone worked there, not proof the note was satisfied — so the result is
 * surfaced as a hint next to the human `verified` status, never as a
 * replacement for it.
 */
export default function useRegionChangeDetection({ threads, versions, enabled = true }) {
    const [results, setResults] = useState({});
    // Held across renders so re-running for a newly added thread does not
    // re-download previews already decoded for the existing ones.
    const cacheRef = useRef(null);

    const versionsById = useMemo(() => {
        const map = {};
        (versions || []).forEach((version) => { map[version.id] = version; });
        return map;
    }, [versions]);

    const activeVersion = useMemo(
        () => (versions || []).find((version) => version.is_active) || null,
        [versions],
    );

    /**
     * The comparisons worth making. A thread is skipped when it has no
     * spatial anchor, or when it was written against the version currently on
     * screen — there is no "before and after" in that case, only a "now".
     */
    const jobs = useMemo(() => {
        if (!enabled || !activeVersion?.preview_url) return [];

        return (threads || []).flatMap((thread) => {
            const originId = thread.origin_version?.id;
            const origin = versionsById[originId];

            if (!origin?.preview_url || origin.id === activeVersion.id) return [];

            // Video markup is anchored to a frame as well as a region, so a
            // still-frame comparison would be meaningless; images only.
            const annotation = (thread.comments || [])
                .flatMap((comment) => comment.annotations || [])
                .find((candidate) => candidate.media_type !== 'video' && candidate.bbox);

            if (!annotation) return [];

            return [{
                threadId: thread.id,
                bbox: annotation.bbox,
                beforeUrl: origin.preview_url,
                afterUrl: activeVersion.preview_url,
                fromVersion: origin.version_number,
                toVersion: activeVersion.version_number,
            }];
        });
    }, [threads, versionsById, activeVersion, enabled]);

    // A stable identity for the job list, so the effect re-runs when the work
    // actually changes rather than on every parent render.
    const jobsKey = useMemo(
        () => jobs.map((job) => `${job.threadId}:${job.beforeUrl}:${job.afterUrl}`).join('|'),
        [jobs],
    );

    useEffect(() => {
        if (jobs.length === 0) {
            setResults({});
            return undefined;
        }

        if (!cacheRef.current) cacheRef.current = createImageCache();
        const loadImage = cacheRef.current;
        let cancelled = false;

        (async () => {
            const next = {};

            for (const job of jobs) {
                try {
                    // Sequential rather than parallel: the cache means the
                    // first job pays for the image loads and the rest are
                    // synchronous pixel work, so concurrency would buy nothing
                    // and would fight for the main thread.
                    // eslint-disable-next-line no-await-in-loop
                    const [beforeImage, afterImage] = await Promise.all([
                        loadImage(job.beforeUrl),
                        loadImage(job.afterUrl),
                    ]);

                    if (cancelled) return;

                    const comparison = compareRegion(beforeImage, afterImage, job.bbox);
                    const region = expandRegion(job.bbox);

                    next[job.threadId] = {
                        ...comparison,
                        fromVersion: job.fromVersion,
                        toVersion: job.toVersion,
                        beforeCrop: regionDataUrl(beforeImage, region),
                        afterCrop: regionDataUrl(afterImage, region),
                    };
                } catch (error) {
                    if (cancelled) return;
                    // A CDN without CORS headers taints the canvas and makes
                    // pixel reads impossible. That is a deployment property,
                    // not a bug, so it is reported as "unavailable" rather
                    // than swallowed or thrown.
                    next[job.threadId] = {
                        status: 'unavailable',
                        reason: isCanvasSecurityError(error) ? 'cross-origin' : 'load-failed',
                        fromVersion: job.fromVersion,
                        toVersion: job.toVersion,
                    };
                }
            }

            if (!cancelled) setResults(next);
        })();

        return () => { cancelled = true; };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [jobsKey]);

    return results;
}
