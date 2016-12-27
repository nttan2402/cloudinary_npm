require('dotenv').load()
https = require('https')
http = require('http')
expect = require("expect.js")
sinon = require('sinon')
cloudinary = require("../cloudinary")
fs = require('fs')
Q = require('q')
_ = require("lodash")
ClientRequest = require('_http_client').ClientRequest

helper = require("./spechelper")
TEST_TAG        = helper.TEST_TAG
IMAGE_FILE      = helper.IMAGE_FILE
LARGE_RAW_FILE  = helper.LARGE_RAW_FILE
LARGE_VIDEO     = helper.LARGE_VIDEO
EMPTY_IMAGE     = helper.EMPTY_IMAGE
RAW_FILE        = helper.RAW_FILE

describe "uploader", ->
  before "Verify Configuration", ->
    config = cloudinary.config(true)
    if(!(config.api_key && config.api_secret))
      expect().fail("Missing key and secret. Please set CLOUDINARY_URL.")

  @timeout helper.TIMEOUT_SHORT
  after ->
    config = cloudinary.config(true)
    if(!(config.api_key && config.api_secret))
      expect().fail("Missing key and secret. Please set CLOUDINARY_URL.")
    cloudinary.v2.api.delete_resources_by_tag(helper.TEST_TAG) unless cloudinary.config().keep_test_products

  ###*
  # Upload an image to be tested on.
  # @callback the callback receives the public_id of the uploaded image
  ###
  upload_image = (callback)->
    cloudinary.v2.uploader.upload IMAGE_FILE, tags: TEST_TAG, (error, result) ->
      expect(error).to.be undefined
      callback(result)

  beforeEach ->
    cloudinary.config(true)

  it "should successfully upload file", (done) ->
    upload_image (result) ->
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()

  it "should successfully upload url", (done) ->
    cloudinary.v2.uploader.upload "http://cloudinary.com/images/old_logo.png", tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()

  describe "rename", ()->
    @timeout helper.TIMEOUT_LONG
    it "should successfully rename a file", (done) ->
      upload_image (result)->
        public_id = result.public_id
        cloudinary.v2.uploader.rename public_id, public_id+"2", (e1, r1) ->
          return done(new Error e1.message) if e1?
          cloudinary.v2.api.resource public_id+"2", (e2, r2) ->
            expect(e2).to.be undefined
            done()

    it "should not rename to an existing public_id", (done)->
      upload_image (result)->
        first_id = result.public_id
        upload_image (result)->
          second_id = result.public_id
          cloudinary.v2.uploader.rename first_id, second_id, (e3, r3) ->
            expect(e3).not.to.be undefined
            done()

    it "should allow to rename to an existing ID, if overwrite is true", (done)->
      upload_image (result)->
        first_id = result.public_id
        upload_image (result)->
          second_id = result.public_id
          cloudinary.v2.uploader.rename first_id, second_id, overwrite: true, (error, result) ->
            expect(error).to.be undefined
            cloudinary.v2.api.resource second_id, (error, result) ->
              expect(result.format).to.eql "png"
              done()

    context ":invalidate", ->
      spy = undefined
      xhr = undefined
      before ->
        spy = sinon.spy(ClientRequest.prototype, 'write')
        xhr = sinon.useFakeXMLHttpRequest()
      after ->
        spy.restore()
        xhr.restore()
      it "should should pass the invalidate value in rename to the server", (done)->
        cloudinary.v2.uploader.rename "first_id", "second_id", invalidate: true, (error, result) ->
          expect(spy.calledWith(sinon.match((arg)-> arg.toString().match(/name="invalidate"/)))).to.be.ok()
          done()

  describe "destroy", ()->
    @timeout helper.TIMEOUT_MEDIUM
    it "should delete a resource", (done)->
      upload_image (result)->
        public_id = result.public_id
        cloudinary.v2.uploader.destroy public_id, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.result).to.eql("ok")
          cloudinary.v2.api.resource public_id, (error, result)->
            expect(error).to.be.ok()
            done()

  it "should successfully call explicit api", (done) ->
    current = this
    cloudinary.v2.uploader.explicit "sample", type: "upload", eager: [crop: "scale", width: "2.0"], (error, result) ->
      unless error?
        url = cloudinary.utils.url "sample",
          type: "upload",
          crop: "scale",
          width: "2.0",
          format: "jpg",
          version: result["version"]
        expect(result.eager[0].url).to.eql(url)
        done()
      else
        if error.code is 420
          console.warn error.message
          console.warn "Try running '#{current.test.title}' again in 10 minutes"
          current.test.pending = true
          done()
        else
          done(new Error error.message)

  it "should support eager in upload", (done) ->
    @timeout helper.TIMEOUT_SHORT
    cloudinary.v2.uploader.upload IMAGE_FILE, eager: [crop: "scale", width: "2.0"], tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      done()

  describe "custom headers", ()->
    it "should support custom headers in object format e.g. {Link: \"1\"}", (done) ->
      cloudinary.v2.uploader.upload IMAGE_FILE, headers: {Link: "1"}, tags: TEST_TAG, (error, result) ->
        return done(new Error error.message) if error?
        done()

    it "should support custom headers as array of strings e.g. [\"Link: 1\"]", (done) ->
      cloudinary.v2.uploader.upload IMAGE_FILE, headers: ["Link: 1"], tags: TEST_TAG, (error, result) ->
        return done(new Error error.message) if error?
        done()

  it "should successfully generate text image", (done) ->
    cloudinary.v2.uploader.text "hello world", tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.width).to.within(50,70)
      expect(result.height).to.within(5,15)
      done()

  it "should successfully upload stream", (done) ->
    stream = cloudinary.v2.uploader.upload_stream tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()
    file_reader = fs.createReadStream(IMAGE_FILE, {encoding: 'binary'})
    file_reader.on 'data', (chunk)-> stream.write(chunk,'binary')
    file_reader.on 'end', -> stream.end()

  describe "tags", ()->
    @timeout helper.TIMEOUT_MEDIUM
    it "should add tags to existing resources", (done) ->
      upload_image (result1)->
        first_id = result1.public_id
        upload_image (result2)->
          second_id = result2.public_id
          cloudinary.v2.uploader.add_tag "tag1", [first_id, second_id], (et1, rt1) ->
            return done(new Error et1.message) if et1?
            cloudinary.v2.api.resource second_id, (error, r1) ->
              return done(new Error error.message) if error
              expect(r1.tags).to.contain("tag1")
              cloudinary.v2.uploader.remove_all_tags [first_id, second_id, 'noSuchId'], (err, res)->
                expect(res["public_ids"]).to.contain(first_id)
                expect(res["public_ids"]).to.contain(second_id)
                expect(res["public_ids"]).to.not.contain('noSuchId')
                cloudinary.v2.api.delete_resources [first_id, second_id], (err, res)->
                  done()

    it "should keep existing tags when adding a new tag", (done)->
      upload_image (result1)->
        public_id = result1.public_id
        cloudinary.v2.uploader.add_tag "tag1", public_id, (error, result)->
          cloudinary.v2.uploader.add_tag "tag2", public_id, (error, result)->
            cloudinary.v2.api.resource public_id, (e1, r1) ->
              expect(r1.tags).to.contain("tag1").and.contain( "tag2")
              done()

    it "should replace existing tag", (done)->
      cloudinary.v2.uploader.upload IMAGE_FILE, tags: ["tag1", "tag2", TEST_TAG], (error, result)->
        return done(new Error error.message) if error?
        public_id = result.public_id
        cloudinary.v2.uploader.replace_tag "tag3Å", public_id, (error, result)-> # TODO this also tests non ascii characters
          return done(new Error error.message) if error?
          cloudinary.v2.api.resource public_id, (error, result) ->
            return done(new Error error.message) if error?
            expect(result.tags).to.eql(["tag3Å"])
            done()

  describe "context", ()->
    @timeout helper.TIMEOUT_MEDIUM
    it "should add context to existing resources", (done) ->
      upload_image (result1)->
        first_id = result1.public_id
        upload_image (result2)->
          second_id = result2.public_id
          cloudinary.v2.uploader.add_context 'alt=testAlt|custom=testCustom', [first_id, second_id], (et1, rt1) ->
            return done(new Error et1.message) if et1?
            cloudinary.v2.api.resource second_id, (error, r1) ->
              return done(new Error error.message) if error
              expect(r1.context.custom.alt).to.equal('testAlt')
              expect(r1.context.custom.custom).to.equal('testCustom')

              cloudinary.v2.uploader.remove_all_context [first_id, second_id, 'noSuchId'], (err, res)->
                expect(res["public_ids"]).to.contain(first_id)
                expect(res["public_ids"]).to.contain(second_id)
                expect(res["public_ids"]).to.not.contain('noSuchId')

                cloudinary.v2.api.resource second_id, (error, r1) ->
                  return done(new Error error.message) if error
                  console.log(r1)
                  expect(r1.context).to.be undefined

                cloudinary.v2.api.delete_resources [first_id, second_id], (err, res)->
                  done()

  it "should support timeouts", (done) ->
    # testing a 1ms timeout, nobody is that fast.
    cloudinary.v2.uploader.upload "http://cloudinary.com/images/old_logo.png", timeout: 1, tags: TEST_TAG, (error, result) ->
      expect(error.http_code).to.eql(499)
      expect(error.message).to.eql("Request Timeout")
      done()

    
  it "should upload a file and base public id on the filename if use_filename is set to true", (done) ->
    @timeout helper.TIMEOUT_MEDIUM
    cloudinary.v2.uploader.upload IMAGE_FILE, use_filename: yes, tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.public_id).to.match /logo_[a-zA-Z0-9]{6}/
      done()


  it "should upload a file and set the filename as the public_id if use_filename is set to true and unique_filename is set to false", (done) ->
    cloudinary.v2.uploader.upload IMAGE_FILE, use_filename: yes, unique_filename: no, tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.public_id).to.eql "logo"
      done()

  describe "allowed_formats", ->
    it "should allow whitelisted formats", (done) ->
      cloudinary.v2.uploader.upload IMAGE_FILE, allowed_formats: ["png"], tags: TEST_TAG, (error, result) ->
        return done(new Error error.message) if error?
        expect(result.format).to.eql("png")
        done()

    it "should prevent non whitelisted formats from being uploaded", (done) ->
      cloudinary.v2.uploader.upload IMAGE_FILE, allowed_formats: ["jpg"], tags: TEST_TAG, (error, result) ->
        expect(error.http_code).to.eql(400)
        done()

    it "should allow non whitelisted formats if type is specified and convert to that type", (done) ->
      cloudinary.v2.uploader.upload IMAGE_FILE, allowed_formats: ["jpg"], format: "jpg", tags: TEST_TAG, (error, result) ->
        return done(new Error error.message) if error?
        expect(result.format).to.eql("jpg")
        done()

  
  it "should allow sending face coordinates", (done) ->
    coordinates = [[120, 30, 109, 150], [121, 31, 110, 151]]
    out_coordinates = [[120, 30, 109, 51], [121, 31, 110, 51]] # coordinates are limited to the image dimensions
    different_coordinates = [[122, 32, 111, 152]]
    custom_coordinates = [1,2,3,4]
    cloudinary.v2.uploader.upload IMAGE_FILE, face_coordinates: coordinates, faces: yes, tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.faces).to.eql(out_coordinates)
      cloudinary.v2.uploader.explicit result.public_id, face_coordinates: different_coordinates, custom_coordinates: custom_coordinates, type: "upload", (error2, result2) ->
        return done(new Error error2.message) if error2?
        cloudinary.v2.api.resource result2.public_id, faces: yes, coordinates: yes, (ierror, info) ->
          return done(new Error ierror.message) if ierror?
          expect(info.faces).to.eql(different_coordinates)
          expect(info.coordinates).to.eql(faces: different_coordinates, custom: [custom_coordinates])
          done()
  
  it "should allow sending context", (done) ->
    @timeout helper.TIMEOUT_LONG
    context = {caption: "some caption", alt: "alternative"}
    cloudinary.v2.uploader.upload IMAGE_FILE, context: context, tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      cloudinary.v2.api.resource result.public_id, context: true, (error, info) ->
        return done(new Error error.message) if error?
        expect(info.context.custom.caption).to.eql("some caption")
        expect(info.context.custom.alt).to.eql("alternative")
        done()


       
  it "should support requesting manual moderation", (done) ->
    cloudinary.v2.uploader.upload IMAGE_FILE, moderation: "manual", tags: TEST_TAG, (error, result) ->
      expect(result.moderation[0].status).to.eql("pending")
      expect(result.moderation[0].kind).to.eql("manual")
      done()

    
  it "should support requesting raw conversion", (done) ->
    cloudinary.v2.uploader.upload RAW_FILE, raw_convert: "illegal", resource_type: "raw", tags: TEST_TAG,  (error, result) ->
      expect(error?).to.be true
      expect(error.message).to.contain "is not a valid"
      done()

    
  it "should support requesting categorization", (done) ->
    cloudinary.v2.uploader.upload IMAGE_FILE, categorization: "illegal", tags: TEST_TAG, (error, result) ->
      expect(error?).to.be true
      expect(error.message).to.contain "is invalid"
      done()

    
  it "should support requesting detection", (done) ->
    cloudinary.v2.uploader.upload IMAGE_FILE, detection: "illegal", tags: TEST_TAG, (error, result) ->
      expect(error).not.to.be undefined
      expect(error.message).to.contain "is not a valid"
      done()

      
  it "should support requesting background_removal", (done) ->
    cloudinary.v2.uploader.upload IMAGE_FILE, background_removal: "illegal", tags: TEST_TAG, (error, result) ->
      expect(error?).to.be true
      expect(error.message).to.contain "is invalid"
      done()

      
  it "should support requesting auto_tagging", (done) ->
    cloudinary.v2.uploader.upload IMAGE_FILE, auto_tagging: 0.5, tags: TEST_TAG, (error, result) ->
      expect(error?).to.be true
      expect(error.message).to.contain "Must use"
      done()


  describe "upload_chunked", ()->
    @timeout helper.TIMEOUT_LONG * 10
    it "should specify chunk size", (done) ->
      fs.stat LARGE_RAW_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_large LARGE_RAW_FILE, {chunk_size: 7000000, timeout: helper.TIMEOUT_LONG, tags: TEST_TAG}, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("4c13724e950abcb13ec480e10f8541f5")
          done()

    it "should return error if value is less than 5MB", (done)->
      fs.stat LARGE_RAW_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_large LARGE_RAW_FILE, {chunk_size: 40000, tags: TEST_TAG}, (error, result) ->
          expect(error.message).to.eql("All parts except last must be larger than 5mb")
          done()

    it "should support uploading a small raw file", (done) ->
      fs.stat RAW_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_large RAW_FILE, tags: TEST_TAG, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("ffc265d8d1296247972b4d478048e448")
          done()

    it "should support uploading a small image file", (done) ->
      fs.stat IMAGE_FILE, (err, stat) ->
        cloudinary.v2.uploader.upload_chunked IMAGE_FILE, tags: TEST_TAG, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("7dc60722d4653261648038b579fdb89e")
          done()

    it "should support uploading large video files", (done) ->
      @timeout helper.TIMEOUT_LONG * 10
      fs.stat LARGE_VIDEO, (err, stat) ->
        return done(new Error err.message) if err?
        cloudinary.v2.uploader.upload_chunked LARGE_VIDEO, {resource_type: 'video', timeout: helper.TIMEOUT_LONG * 10, tags: TEST_TAG}, (error, result) ->
          return done(new Error error.message) if error?
          expect(result.bytes).to.eql(stat.size)
          expect(result.etag).to.eql("ff6c391d26be0837ee5229885b5bd571")
          cloudinary.v2.uploader.destroy result.public_id, ()->
            done()

  it "should support unsigned uploading using presets", (done) ->
    @timeout helper.TIMEOUT_LONG
    cloudinary.v2.api.create_upload_preset folder: "upload_folder", unsigned: true, tags: TEST_TAG, (error, preset) ->
      cloudinary.v2.uploader.unsigned_upload IMAGE_FILE, preset.name, tags: TEST_TAG, (error, result) ->
        return done(new Error error.message) if error?
        cloudinary.v2.api.delete_upload_preset preset.name, ->
          expect(result.public_id).to.match /^upload_folder\/[a-z0-9]+$/
          done()

  it "should reject promise if error code is returned from the server", (done) ->
    cloudinary.v2.uploader.upload(EMPTY_IMAGE, tags: helper.TEST_TAG)
    .then ->
      expect().fail("server should return an error when uploading an empty file")
    .catch (error)->
      expect(error.message).to.contain "empty"
    .finally ->
      done()

  it "should successfully upload with pipes", (done) ->
    @timeout helper.TIMEOUT_LONG
    upload = cloudinary.v2.uploader.upload_stream tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()
    file_reader = fs.createReadStream(IMAGE_FILE)
    file_reader.pipe(upload)

  it "should fail with http.Agent (non secure)", (done) ->
    if process.version <= 'v.11.11'
      @timeout helper.TIMEOUT_LONG
      upload = cloudinary.v2.uploader.upload_stream agent:new http.Agent, tags: TEST_TAG, (error, result) ->
        expect(error).to.be.ok()
        expect(error.message).to.match(/socket hang up|ECONNRESET/)
        done()

      file_reader = fs.createReadStream(IMAGE_FILE)
      file_reader.pipe(upload)
    else
      # Node > 0.11.11
      @timeout helper.TIMEOUT_LONG
      expect(cloudinary.v2.uploader.upload_stream).withArgs({agent:new http.Agent},(error, result) ->
        done()
      ).to.throwError()
      done()

  it "should successfully override https agent", (done) ->
    upload = cloudinary.v2.uploader.upload_stream agent:new https.Agent, tags: TEST_TAG, (error, result) ->
      return done(new Error error.message) if error?
      expect(result.width).to.eql(241)
      expect(result.height).to.eql(51)
      expected_signature = cloudinary.utils.api_sign_request({public_id: result.public_id, version: result.version}, cloudinary.config().api_secret)
      expect(result.signature).to.eql(expected_signature)
      done()
    file_reader = fs.createReadStream(IMAGE_FILE)
    file_reader.pipe(upload)

  context ":responsive_breakpoints", ->
    context ":create_derived", ->
      it 'should return a responsive_breakpoints in the response', (done)->
        cloudinary.v2.uploader.upload IMAGE_FILE, responsive_breakpoints: {create_derived: false }, tags: TEST_TAG, (error, result)->
          return done(new Error error.message) if error?
          expect(result).to.have.key('responsive_breakpoints')
          done()

  describe "explicit", ->
    spy = undefined
    xhr = undefined
    before ->
      xhr = sinon.useFakeXMLHttpRequest()
      spy = sinon.spy(ClientRequest.prototype, 'write')
    after ->
      spy.restore()
      xhr.restore()

    describe ":invalidate", ->
      it "should should pass the invalidate value to the server", ()->
        cloudinary.v2.uploader.explicit "cloudinary", type: "twitter_name", eager: [crop: "scale", width: "2.0"], invalidate: true, tags: [TEST_TAG]
        sinon.assert.calledWith(spy, sinon.match((arg)-> arg.toString().match(/name="invalidate"\s*1/)))



