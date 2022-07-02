//Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//SPDX-License-Identifier: MIT-0

var express = require("express");
var app = express();
var AWSXRay = require('aws-xray-sdk');

app.use(AWSXRay.express.openSegment('Product-Detail-V2'));

app.get("/catalogDetail", (req, res, next) => {
  console.log("Catalog Detail Version 2 Get Request Successful");
  res.json({
             "version":"2",
             "vendors":[ "ABC.com", "XYZ.com" ]
              } )
});

app.get("/ping", (req, res, next) => {
  res.json("Healthy")
});

app.use(AWSXRay.express.closeSegment());

app.listen(3000, () => {
 console.log("Server running on port 3000");
});