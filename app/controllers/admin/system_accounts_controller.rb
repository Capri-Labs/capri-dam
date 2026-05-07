module Admin
  class SystemAccountsController < BaseController
    before_action :set_app, only: [:show, :destroy]

    def new
      @app = Doorkeeper::Application.new
    end

    def create
      @app = Doorkeeper::Application.new(app_params)
      # System accounts use the 'out-of-band' URI for machine-to-machine
      @app.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
      @app.scopes = "read write" # Defaulting to full access for now

      if @app.save
        redirect_to settings_path, notice: "System account '#{@app.name}' created! Please save your Secret now."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      # Fetched via before_action :set_app
    end

    def destroy
      @app.destroy
      redirect_to settings_path, notice: "System Account revoked successfully."
    end

    private

    def set_app
      @app = Doorkeeper::Application.find(params[:id])
    end

    def app_params
      params.require(:doorkeeper_application).permit(:name)
    end
  end
end