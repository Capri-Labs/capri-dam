# GraphQL mutation — create a new local DAM user.
#
# Only admins may invoke this mutation.  A temporary password is generated
# and the +force_password_change+ flag is set so the user must reset it on
# first login.
module Mutations
  class CreateUser < Mutations::BaseMutation
    description "Create a new local DAM user account (admin only)"

    argument :email,      String, required: true
    argument :first_name, String, required: true
    argument :last_name,  String, required: true
    argument :department, String, required: false
    argument :role,       String, required: false, default_value: 'viewer'
    argument :admin,      Boolean, required: false, default_value: false
    argument :group_ids,  [ID],   required: false, default_value: []

    field :user,   Types::UserType, null: true
    field :errors, [String],        null: false

    def resolve(email:, first_name:, last_name:, department: nil,
                role: 'viewer', admin: false, group_ids: [])
      unless context[:current_user]&.admin?
        return { user: nil, errors: ["Unauthorized"] }
      end

      temp_password = SecureRandom.base36(12)
      user = User.new(
        email:                 email,
        first_name:            first_name,
        last_name:             last_name,
        name:                  "#{first_name} #{last_name}".strip,
        department:            department,
        role:                  role,
        admin:                 admin,
        password:              temp_password,
        password_confirmation: temp_password,
        active:                true,
        force_password_change: true
      )

      user.user_group_ids = group_ids.map(&:to_i) if group_ids.any?

      if user.save
        EmailOrchestrator.trigger('user_created', user.email,
          { 'user' => { 'first_name' => first_name, 'temp_password' => temp_password } })
        { user: user, errors: [] }
      else
        { user: nil, errors: user.errors.full_messages }
      end
    end
  end
end

