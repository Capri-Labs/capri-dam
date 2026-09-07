# Lets a comment and a thread be attributed to an external {ReviewGuest}
# instead of a {User}.
#
# The comments table was already half-ready for this: +author_id+ is nullable
# and +agent_type+ distinguishes a person from software, so a comment without a
# User row is an established shape rather than a new one. Threads were not —
# +created_by_id+ was NOT NULL, which would have made it impossible for a guest
# to open a thread at all.
#
# ATTRIBUTING A GUEST THREAD TO THE LINK'S CREATOR WOULD HAVE AVOIDED THIS
# MIGRATION, AND WOULD HAVE BEEN WRONG
# -----------------------------------------------------------------------
# It would have recorded the account manager who sent the link as the author of
# the client's objection. Review history is evidence; misattributing it to make
# a NOT NULL constraint work is not a trade worth making.
class AddGuestAuthorshipToComments < ActiveRecord::Migration[8.1]
  def change
    add_reference :comments, :review_guest, type: :uuid, foreign_key: true, null: true

    add_reference :comment_threads, :created_by_guest,
                  type: :uuid, null: true,
                  foreign_key: { to_table: :review_guests }

    # A thread is now authored by exactly one of a user or a guest.
    change_column_null :comment_threads, :created_by_id, true

    add_check_constraint :comment_threads,
                         "created_by_id IS NOT NULL OR created_by_guest_id IS NOT NULL",
                         name: "comment_threads_have_an_author"

    # Which link a guest thread arrived through, so a revoked link's
    # contributions can be found and reviewed after the fact.
    add_reference :comment_threads, :review_link, type: :uuid, foreign_key: true, null: true
  end
end
