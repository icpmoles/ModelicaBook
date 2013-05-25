within ModelicaByExample.Chapter1.SimpleExample;
model FirstOrderDocumented "A simple first order differential equation"
  Real x "Our unknown (state) variable";
equation
  der(x) = 1-x "Drives value of x toward 1.0";
end FirstOrderDocumented;
