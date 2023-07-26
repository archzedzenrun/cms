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

# Path to file history based on development or test environment
def history_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data_history", __FILE__)
  else
    File.expand_path("../data_history", __FILE__)
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

# User list (admin only)
get "/users/list" do
  @user_list = load_user_credentials.sort
  erb :userlist
end

# Changes user list (admin only)
post "/users/list" do
  if load_user_credentials != params[:user_list]
    session[:message] = "User list has been updated."
  end
  create_document("../users.yml", params[:user_list].to_yaml )
  redirect "/"
end

# User sign up page
get "/users/signup" do
  erb :signup
end

# Deletes a user from the user list (admin only)
post "/users/delete/:user" do
  users = load_user_credentials
  users.delete(params[:user])
  create_document("../users.yml", users.to_yaml )
  session[:message] = "User #{params[:user]} deleted."
  redirect "/users/list"
end

# Encrypts string
def encrypt_password(password)
  BCrypt::Password.create(password)
end

# Checks if password is valid
def valid_password?(password)
  contains_symbol = password.match?(/^[a-zA-Z0-9]/)
  contains_number = password.match?(/[0-9]/)
  contains_upcase = password.match?(/[A-Z]/)
  contains_symbol && contains_number && contains_upcase
end

# Adds user info to users.yml
post "/users/signup" do
  users = load_user_credentials
  if users.key?(params[:signup_name])
    session[:message] = "Username already exists."
    erb :signup
  elsif params[:signup_password] != params[:signup_password2]
    session[:message] = "Passwords don't match."
    erb :signup
  elsif !valid_password?(params[:signup_password])
    session[:message] = "Passwords must contain an uppercase letter, a number, and a symbol."
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
    session[:message] = "Welcome #{username}!"
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
  erb :index, layout: false
end

# Create a new file page
get "/new" do
  require_signed_in
  erb :new
end

# Creates a new file
def create_document(name, content = "")
  File.open(File.join(data_path, name), "w") do |file|
    file.write(content)
  end
end

# Creates a history directory for a file
def create_history_directory(name)
  path = File.join(history_path, name)
  FileUtils.mkdir(path) unless File.exist?(path)
end

# Deletes a files history directory
def delete_history_directory(name)
  path = File.join(history_path, name)
  FileUtils.rm_rf(path) if Dir.exist?(path)
end

# Verifies valid file extension
def valid_file?(name)
  File.extname(name) == '.txt' || File.extname(name) == '.md'
end

# Checks if a file name already exists
def file_exists?(name)
  pattern = File.join(data_path, "*")
  files = Dir.glob(pattern).map { |path| File.basename(path) }
  files.include?(name)
end

# Create a new file
post "/create" do
  require_signed_in
  file_name = params[:file_name]

  if File.basename(file_name, ".*").strip.empty?
    session[:message] = "A name is required."
    status(422)
    erb :new
  elsif file_exists?(file_name)
    session[:message] = "#{file_name} already exists."
    status(422)
    erb :new
  elsif !valid_file?(file_name)
    session[:message] = "Invalid file name (.txt and .md files only)."
    status(422)
    erb :new
  else
    create_history_directory(file_name)
    create_document(file_name)
    session[:message] = "#{file_name} has been created."
    redirect "/"
  end
end

# Delete a files history
post "/:file_name/history/delete" do
  file_name = params[:file_name]
  pattern = File.join(history_path, file_name, "*")
  files = Dir.glob(pattern).each { |path| File.delete(path) }
  session[:message] = "#{file_name} history deleted."
  redirect "/#{file_name}/history"
end

# View file change history
get "/:file_name/history" do
  pattern = File.join(history_path, params[:file_name], "*")
  @files = Dir.glob(pattern).map { |path| File.basename(path) }.sort
  @files.reverse! if params[:sort] == 'desc'
  erb :history
end

# View contents of a history file
get "/:file_name/history/:history_name" do
  path = File.join(history_path, params[:file_name], params[:history_name])
  load_file_content(path)
end

# Delete a file
post "/:file_name/delete" do
  require_signed_in
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)
  File.delete(file_path)
  delete_history_directory(file_name)
  session[:message] = "#{file_name} has been deleted."
  redirect "/"
end

# Adds "_copy" to the end of a file name
def duplicate_file_name(name)
  basename = File.basename(name, ".*") + "_copy"
  extension = File.extname(name)
  basename + extension
end

def history_file_version_number(file_name)
  file_name.chars.each_with_object('') do |char, version|
    version << char
    return version if char == '_'
  end
end

def duplicate_history_files(file_name)
  dupe_name = duplicate_file_name(file_name)
  history_path_dupe_name = File.join(history_path, dupe_name)
  pattern = File.join(history_path, file_name, "*")
  Dir.glob(pattern).each do |original_path|
    base_name = File.basename(original_path, ".*")
    version = history_file_version_number(base_name)
    new_name = version + dupe_name
    history_path_new = File.join(history_path_dupe_name, new_name)
    FileUtils.cp(original_path, history_path_new)
  end
end

# Duplicate a file
post "/:file_name/duplicate" do
  require_signed_in

  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)
  duplicate_name = duplicate_file_name(file_name)
  file_path_new = File.join(data_path, duplicate_name)

  FileUtils.cp(file_path, file_path_new)
  create_history_directory(duplicate_name)
  duplicate_history_files(file_name)

  session[:message] = "A copy of #{file_name} was created."
  redirect "/"
end

# Renders markdown files
def render_md(file)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(file)
end

# Renders markdown(.md) or text(.txt) files.
def load_file_content(file_path)
  file_content = File.read(file_path)
  case File.extname(file_path)
  when ".md" then erb render_md(file_content), layout: false
  when ".txt" then
    headers["Content-Type"] = "text/plain"
    file_content
  end
end

# Read the contents of a file
get "/:file_name" do
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{file_name} does not exist."
    redirect "/"
  end
end

# Edit the contents of a file
get "/:file_name/edit" do
  require_signed_in
  @file_name = params[:file_name]
  file_path = File.join(data_path, @file_name)
  @file_content = File.read(file_path)
  erb :edit
end

# Rename file page
get "/:file_name/rename" do
  require_signed_in
  erb :rename
end

# Renames history files
def rename_history_files(file_name, file_name_new)
  pattern = File.join(history_path, file_name, "*")
  Dir.glob(pattern).each do |original_path|
    base_name = File.basename(original_path, ".*")
    version = history_file_version_number(base_name)
    new_name = version + file_name_new
    history_path_new = File.join(history_path, file_name_new, new_name)
    FileUtils.mv(original_path, history_path_new)
  end
end

# Rename a file
post "/:file_name/rename" do
  file_name = params[:file_name]
  file_name_new = params[:new_name]
  file_path = File.join(data_path, file_name)
  file_path_new = File.join(data_path, file_name_new)
  if !valid_file?(file_name_new)
    session[:message] = "Invalid file name (.txt and .md files only)."
    status(422)
    erb :rename
  else
    create_history_directory(file_name_new)
    rename_history_files(file_name, file_name_new)
    delete_history_directory(file_name)
    FileUtils.mv(file_path, file_path_new)
    session[:message] = "#{file_name} renamed to #{file_name_new}"
    redirect "/"
  end
end

# Adds version number to a file name
def file_version_number(file_name)
  pattern = File.join(history_path, file_name, "*")
  files = Dir.glob(pattern).map { |path| File.basename(path) }
  files = ['0_'] if files.empty?
  version = ''
  files.last.each_char do |char|
    break if char == "_"
    version << char
  end
  version = "#{version.to_i + 1}_"
end

# Writes content to file
def write_file_content(file_name, content_original, content_new)
  version_name = file_version_number(file_name) + file_name
  file_path = File.join(data_path, file_name)
  file_history_path = File.join(history_path, file_name, version_name)
  File.write(file_history_path, content_original)
  File.write(file_path, content_new)
end

# Updates/writes content of a file
post "/:file_name" do
  require_signed_in
  file_name = params[:file_name]
  file_path = File.join(data_path, file_name)
  content_original = File.read(file_path)
  content_new = params[:content]

  if content_original != content_new
    write_file_content(file_name, content_original, content_new)
    session[:message] = "#{file_name} has been updated."
  end

  redirect "/"
end
