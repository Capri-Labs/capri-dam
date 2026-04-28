module Admin
  class SystemAccountsController < BaseController
    def new
      @app = Doorkeeper::Application.new
    end

    def create
      @app = Doorkeeper::Application.new(app_params)
      # System accounts use the 'out-of-band' URI for machine-to-machine
      @app.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
      @app.scopes = "read write" # Defaulting to full access for now

      if @app.save
        redirect_to admin_dashboard_path, notice: "Account created! ID: #{@app.uid}"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
      @app = Doorkeeper::Application.find(params[:id])
      # We show the secret here. In a production app, you might only
      # allow this if the app was created within the last 30 seconds.
    end

    def destroy
      @app = Doorkeeper::Application.find(params[:id])
      @app.destroy
      redirect_to admin_dashboard_path, notice: "Account revoked."
    end

    private

    def app_params
      params.require(:doorkeeper_application).permit(:name)
    end
  end
end