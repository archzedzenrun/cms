require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, '19390b1c59d812f894da0c2480155c5ea0089361ed1f17f632998d2fd7f19147'
end

# Path to save files based on development or test environment
def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

# Checks if user is signed in
def require_signed_in
  unless session[:username]
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

# Loads user list file
def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/users.yml", __FILE__)
  else
    File.expand_path("../users.yml", __FILE__)
  end
  YAML.load_file(credentials_path)
end

# User sign up page
get "/users/signup" do
  erb :signup
end

def encrypt_password(password)
  BCrypt::Password.create(password)
end

# Adds user info to users.yml
post "/users/signup" do
  users = load_user_credentials
  if users.key?(params[:signup_name])# == true
    session[:message] = "Username already exists."
    erb :signup
  else
    session[:message] = "Sign up was successful."
    name = params[:signup_name]
    password = BCrypt::Password.create(params[:signup_password]).to_s
    users[name] = password
    create_document("../users.yml", users.to_yaml )
    redirect "/"
  end

end

# Log in page
get "/users/signin" do
  erb :login
end

# Verifies credentials
def valid_credentials?(username, password)
  credentials = load_user_credentials
  bcrypt_password = BCrypt::Password.create(password)
  credentials.key?(username) && bcrypt_password == password
end

# Submitted Log in page
post "/users/signin" do
  username = params[:username]
  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = "Welcome!"
    redirect "/"
  else
    session[:message] = "Invalid credentials."
    status(422)
    erb :login
  end
end

# Log out page
post "/users/signout" do
  session.delete(:username)
  session[:message] = "You have been signed out."
  redirect "/"
end

# List of files in the data directory
get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map { |path| File.basename(path) }.sort
  @files.reverse! if params[:sort] == 'desc'
  erb :index
end

# Create a new file page
get "/new" do
  require_signed_in
  erb :new
end

# Verifies valid file extension
def valid_file?(name)
  valid_ext = ['.txt', '.md']
  valid_ext.any? { |ext| name.include?(ext) } && name.count('.') == 1
end

# Creates a new file
def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

# Create a new file
post "/create" do
  require_signed_in
  if params[:file_name].empty?
    session[:message] = "A name is required."
    status(422)
    erb :new
  elsif !valid_file?(params[:file_name])
    session[:message] = "Invalid file name (.txt and .md files only)."
    status(422)
    erb :new
  else
    create_document(params[:file_name])
    session[:message] = "#{params[:file_name]} has been created."
    redirect "/"
  end
end

# Delete a file
post "/:file_name/delete" do
  require_signed_in
  file_path = File.join(data_path, params[:file_name])
  File.delete(file_path)
  session[:message] = "#{params[:file_name]} has been deleted."
  redirect "/"
end

# Duplicate a file
post "/:file_name/duplicate" do
  require_signed_in
  file_path = File.join(data_path, params[:file_name])
  name_copy = "copy_" + params[:file_name]
  new_path = File.join(data_path, name_copy)
  FileUtils.cp(file_path, new_path)
  session[:message] = "A copy of #{params[:file_name]} was created."
  redirect "/"
end

# Renders markdown files
def render_md(file)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(file)
end

# Renders markdown if extension is .md, otherwise reads txt file
def load_file_content(file_path)
  file_content = File.read(file_path)
  case File.extname(file_path)
  when ".md" then erb render_md(file_content)
  when ".txt" then
    headers["Content-Type"] = "text/plain"
    file_content
  end
end

# Read the contents of a file
get "/:file_name" do
  file_path = File.join(data_path, params[:file_name])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:file_name]} does not exist."
    redirect "/"
  end
end

# Edit the contents of a file
get "/:file_name/edit" do
  require_signed_in
  file_path = File.join(data_path, params[:file_name])
  @file_name = params[:file_name]
  @file_content = File.read(file_path)
  erb :edit
end

# Edit file name page
get "/:file_name/rename" do
  require_signed_in
  erb :rename
end

# Change file name
post "/:file_name/rename" do
  old_path = File.join(data_path, params[:file_name])
  new_path = File.join(data_path, params[:new_name])
  if !valid_file?(params[:new_name])
    session[:message] = "Invalid file name (.txt and .md files only)."
    status(422)
    erb :rename
  else
    FileUtils.mv(old_path, new_path)
    session[:message] = "#{params[:file_name]} renamed to #{params[:new_name]}"
    redirect "/"
  end
end

# Updates/writes content of a file
post "/:file_name" do
  require_signed_in
  file_name = params[:file_name]
  file_path = File.join(data_path, params[:file_name])
  original_content = File.read(file_path)
  new_content = params[:content]

  if original_content != new_content
    File.write(file_path, params[:content])
    session[:message] = "#{file_name} has been updated."
  end

  redirect "/"
end
