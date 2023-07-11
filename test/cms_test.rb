ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    create_document("history.txt", "This is history")
    create_document("about.md", "<h1>Ruby is...</h1>")
    create_document("changes.txt")
    #@original_history_file = File.read("../test/data/history.txt")
  end

  def teardown
    #File.write("./data/history.txt", @original_history_file)
    FileUtils.rm_rf(data_path)
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_file_index
    get "/"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "history.txt")
    assert_includes(last_response.body, "changes.txt")
    assert_includes(last_response.body, "about.md")
  end

  def test_reading_a_file
    get "./history.txt"
    assert_equal(200, last_response.status)
    assert_equal('text/plain', last_response["Content-Type"])
    assert_includes(last_response.body, "This is history")
  end

  def test_editing_a_file
    get "/history.txt/edit", {}, admin_session
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<textarea")
    assert_includes(last_response.body, "<button type=")
  end

  def test_editing_a_file_signed_out
    get "/history.txt/edit"
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_updating_a_file
    post "/history.txt", { content: "new content" }, admin_session
    assert_equal(302, last_response.status)
    assert_equal("history.txt has been updated.", session[:message])

    get "/history.txt"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "new content")
  end

  def test_updating_a_file_signed_out
    post "/history.txt", { content: "new content" }
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_nonexistant_file
    get "/nofile.txt"
    assert_equal(302, last_response.status)
    assert_equal("nofile.txt does not exist.", session[:message])
  end

  def test_view_markdown_file
    get "/about.md"
    assert_equal(200, last_response.status)
    assert_equal("text/html;charset=utf-8", last_response["Content-Type"])
    assert_includes(last_response.body, "<h1>Ruby is...</h1>")
  end

  def test_new_file_page
    get "/new", {}, admin_session
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
    assert_includes(last_response.body, "Add a new document:")
  end

  def test_new_file_page_signed_out
    get "/new"
    assert_equal(302, last_response.status)
    assert_includes("You must be signed in to do that.", session[:message])
  end

  def test_create_file
    post "/create", { file_name: "test.txt" }, admin_session
    assert_equal(302, last_response.status)
    assert_equal("test.txt has been created.", session[:message])

    get "/"
    assert_includes(last_response.body, "test.txt")
  end

  def test_create_file_signed_out
    post "/create", { file_name: "test.txt" }
    assert_equal(302, last_response.status)
    assert_equal("You must be signed in to do that.", session[:message])
  end

  def test_create_file_empty_filename
    post "/create", { file_name: "" }, admin_session
    assert_equal(422, last_response.status)
    assert_includes(last_response.body, "A name is required.")
  end

  def test_delete_file
    post "/create", { file_name: "test.txt" }, admin_session
    assert_equal(302, last_response.status)
    assert_equal("test.txt has been created.", session[:message])

    post "/test.txt/delete"
    assert_equal(302, last_response.status)
    assert_equal("test.txt has been deleted.", session[:message])
  end

  def test_signin_page
    get "/users/signin"
    assert_equal(200, last_response.status)
    assert_includes(last_response.body, "<input")
  end

  def test_signin
    post "/users/signin", username: "admin", password: "secret"
    assert_equal(302, last_response.status)
    assert_equal("Welcome!", session[:message])
    assert_equal("admin", session[:username])

    get last_response["Location"]
    assert_includes(last_response.body, "Signed in as admin.")
  end

  def test_signin_bad_credentials
    post "users/signin", username: "", password: ""
    assert_equal(422, last_response.status)
    assert_nil(session[:username])
    assert_includes(last_response.body, "Invalid credentials.")
  end

  def test_signout
    get "/", {}, {"rack.session" => { username: "admin"} }
    assert_includes(last_response.body, "Signed in as admin.")

    post "users/signout"
    assert_nil(session[:username])
    assert_equal("You have been signed out.", session[:message])

    get last_response["Location"]
    assert_includes(last_response.body, "Sign In")
  end
end
