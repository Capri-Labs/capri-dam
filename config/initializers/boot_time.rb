# frozen_string_literal: true

# Records when this process finished booting.
#
# Process uptime is the first thing asked when a node starts behaving oddly —
# a "restart loop" and a "memory leak" look identical until you know whether
# the process is four minutes or four days old. Ruby exposes no portable way to
# read its own start time (`/proc` is Linux-only and shelling out to `ps` is
# both slow and a needless command injection surface), so it is captured here.
#
# `to_prepare` would re-run on every code reload in development and report the
# age of the last edit instead of the age of the process.
Rails.application.config.x.booted_at = Time.current
