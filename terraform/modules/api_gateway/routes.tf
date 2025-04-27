# Create routes for each path and method combination
resource "aws_apigatewayv2_route" "routes" {
  for_each = {
    for idx, route in flatten([
      for route_key, route in var.routes : [
        for method in route.methods : {
          key           = "${route_key}_${method}"
          path          = route.path
          method        = method
          function_name = route.function_name
          authorization = route.authorization
          authorizer_id = route.authorizer_id
        }
      ]
    ]) : route.key => route
  }
  
  api_id    = local.http_api_id
  route_key = "${each.value.method} ${each.value.path}"
  
  target = "integrations/${aws_apigatewayv2_integration.lambda[each.value.function_name].id}"
  
  authorization_type = each.value.authorization
  authorizer_id     = each.value.authorization != "NONE" ? each.value.authorizer_id : null
} 