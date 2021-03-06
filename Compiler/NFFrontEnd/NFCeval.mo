/*
 * This file is part of OpenModelica.
 *
 * Copyright (c) 1998-2014, Open Source Modelica Consortium (OSMC),
 * c/o Linköpings universitet, Department of Computer and Information Science,
 * SE-58183 Linköping, Sweden.
 *
 * All rights reserved.
 *
 * THIS PROGRAM IS PROVIDED UNDER THE TERMS OF GPL VERSION 3 LICENSE OR
 * THIS OSMC PUBLIC LICENSE (OSMC-PL) VERSION 1.2.
 * ANY USE, REPRODUCTION OR DISTRIBUTION OF THIS PROGRAM CONSTITUTES
 * RECIPIENT'S ACCEPTANCE OF THE OSMC PUBLIC LICENSE OR THE GPL VERSION 3,
 * ACCORDING TO RECIPIENTS CHOICE.
 *
 * The OpenModelica software and the Open Source Modelica
 * Consortium (OSMC) Public License (OSMC-PL) are obtained
 * from OSMC, either from the above address,
 * from the URLs: http://www.ida.liu.se/projects/OpenModelica or
 * http://www.openmodelica.org, and in the OpenModelica distribution.
 * GNU version 3 is obtained from: http://www.gnu.org/copyleft/gpl.html.
 *
 * This program is distributed WITHOUT ANY WARRANTY; without
 * even the implied warranty of  MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE, EXCEPT AS EXPRESSLY SET FORTH
 * IN THE BY RECIPIENT SELECTED SUBSIDIARY LICENSE CONDITIONS OF OSMC-PL.
 *
 * See the full OSMC Public License conditions for more details.
 *
 */

encapsulated package NFCeval

import Binding = NFBinding;
import ComponentRef = NFComponentRef;
import Error;
import NFComponent.Component;
import Expression = NFExpression;
import NFInstNode.InstNode;
import Operator = NFOperator;
import Typing = NFTyping;
import NFCall.Call;
import Dimension = NFDimension;
import Type = NFType;
import NFTyping.ExpOrigin;
import ExpressionSimplify;
import NFPrefixes.Variability;

protected
import NFFunction.Function;
import SimplifyExp = NFSimplifyExp;
import List;

public
uniontype EvalTarget
  record DIMENSION
    InstNode component;
    Integer index;
    Expression exp;
    SourceInfo info;
  end DIMENSION;

  record ATTRIBUTE
    Binding binding;
  end ATTRIBUTE;

  record RANGE
    SourceInfo info;
  end RANGE;

  record CONDITION
    SourceInfo info;
  end CONDITION;

  record GENERIC
    SourceInfo info;
  end GENERIC;

  record IGNORE_ERRORS end IGNORE_ERRORS;

  function isRange
    input EvalTarget target;
    output Boolean isRange;
  algorithm
    isRange := match target
      case RANGE() then true;
      else false;
    end match;
  end isRange;

  function hasInfo
    input EvalTarget target;
    output Boolean hasInfo;
  algorithm
    hasInfo := match target
      case DIMENSION() then true;
      case ATTRIBUTE() then true;
      case RANGE() then true;
      case CONDITION() then true;
      else false;
    end match;
  end hasInfo;

  function getInfo
    input EvalTarget target;
    output SourceInfo info;
  algorithm
    info := match target
      case DIMENSION() then target.info;
      case ATTRIBUTE() then Binding.getInfo(target.binding);
      case RANGE() then target.info;
      case CONDITION() then target.info;
    end match;
  end getInfo;
end EvalTarget;

function evalExp
  input output Expression exp;
  input EvalTarget target;
algorithm
  exp := match exp
    local
      InstNode c;
      Binding binding;
      Expression exp1, exp2, exp3;
      list<Expression> expl = {};
      Call call;
      Component comp;
      Option<Expression> oexp;
      ComponentRef cref;
      Dimension dim;

    case Expression.CREF(cref = cref as ComponentRef.CREF(node = c as InstNode.COMPONENT_NODE(),
                                                          origin = NFComponentRef.Origin.CREF))
      algorithm
        Typing.typeComponentBinding(c, ExpOrigin.CLASS);
        binding := Component.getBinding(InstNode.component(c));
        exp1 := evalBinding(binding, exp, target);
      then
        Expression.applySubscripts(cref.subscripts, exp1);

    case Expression.TYPENAME()
      then evalTypename(exp.ty, exp, target);

    case Expression.ARRAY()
      algorithm
        for e in exp.elements loop
          exp1 := evalExp(e, target);
          expl := exp1 :: expl;
        end for;
      then Expression.ARRAY(exp.ty, listReverse(expl));

    // Ranges could be evaluated into arrays, but that's less efficient in some
    // cases. So here we just evaluate the range's expressions, and let the
    // caller worry about vectorization.
    case Expression.RANGE()
      algorithm
        exp1 := evalExp(exp.start, target);
        oexp := evalExpOpt(exp.step, target);
        exp3 := evalExp(exp.stop, target);
      then
        Expression.RANGE(exp.ty, exp1, oexp, exp3);

    case Expression.RECORD()
      algorithm
        Error.addInternalError("Unimplemented case for " + Expression.toString(exp) + " in " + getInstanceName(), sourceInfo());
      then fail();

    case Expression.CALL()
      then evalCall(exp.call, target);

    case Expression.SIZE(dimIndex = SOME(exp1))
      algorithm
        dim := listGet(Type.arrayDims(Expression.typeOf(exp.exp)), Expression.toInteger(evalExp(exp1, target)));
      then
        if Dimension.isKnown(dim) then Expression.INTEGER(Dimension.size(dim)) else exp;

    case Expression.SIZE()
      algorithm
        expl := list(Expression.INTEGER(Dimension.size(d)) for d in Type.arrayDims(Expression.typeOf(exp.exp)));
        dim := Dimension.INTEGER(listLength(expl), Variability.PARAMETER);
      then
        Expression.ARRAY(Type.ARRAY(Type.INTEGER(), {dim}), expl);

    case Expression.BINARY()
      algorithm
        exp1 := evalExp(exp.exp1, target);
        exp2 := evalExp(exp.exp2, target);
      then Expression.BINARY(exp1, exp.operator, exp2);

    case Expression.UNARY()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then Expression.UNARY(exp.operator, exp1);

    case Expression.LBINARY()
      algorithm
        exp1 := evalExp(exp.exp1, target);
        exp2 := evalExp(exp.exp2, target);
      then Expression.LBINARY(exp1, exp.operator, exp2);

    case Expression.LUNARY()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then Expression.LUNARY(exp.operator, exp1);

    case Expression.RELATION()
      algorithm
        exp1 := evalExp(exp.exp1, target);
        exp2 := evalExp(exp.exp2, target);
      then Expression.RELATION(exp1, exp.operator, exp2);

    case Expression.IF()
      algorithm
        exp1 := evalExp(exp.condition, target);
        exp2 := evalExp(exp.trueBranch, target);
        exp3 := evalExp(exp.falseBranch, target);
      then Expression.IF(exp1, exp2, exp3);

    case Expression.CAST()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then Expression.CAST(exp.ty, exp1);

    case Expression.UNBOX()
      algorithm
        exp1 := evalExp(exp.exp, target);
      then Expression.UNBOX(exp1, exp.ty);

    else exp;
  end match;
end evalExp;

function evalExpOpt
  input output Option<Expression> oexp;
  input EvalTarget target;
algorithm
  oexp := match oexp
    local
      Expression e;

    case SOME(e) then SOME(evalExp(e, target));
    else oexp;
  end match;
end evalExpOpt;

function evalBinding
  input Binding binding;
  input Expression originExp "The expression the binding came from, e.g. a cref.";
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := match binding
    case Binding.TYPED_BINDING() then evalExp(binding.bindingExp, target);
    case Binding.UNBOUND()
      algorithm
        printUnboundError(target, originExp);
      then
        originExp;
    else
      algorithm
        Error.addInternalError(getInstanceName() + " failed on untyped binding", sourceInfo());
      then
        fail();
  end match;
end evalBinding;

function evalTypename
  input Type ty;
  input Expression originExp;
  input EvalTarget target;
  output Expression exp;
protected
  list<Expression> lits;
algorithm
  // Only expand the typename into an array if it's used as a range, and keep
  // them as typenames when used as e.g. dimensions.
  if not EvalTarget.isRange(target) then
    exp := originExp;
  else
    exp := match ty
      case Type.ARRAY(elementType = Type.BOOLEAN())
        then Expression.ARRAY(ty, {Expression.BOOLEAN(false), Expression.BOOLEAN(true)});

      case Type.ARRAY(elementType = Type.ENUMERATION())
        algorithm
          lits := Expression.makeEnumLiterals(ty.elementType);
        then
          Expression.ARRAY(ty, lits);

      else
        algorithm
          Error.addInternalError(getInstanceName() + " got invalid typename", sourceInfo());
        then
          fail();

    end match;
  end if;
end evalTypename;

function evalCall
  input Call call;
  input EvalTarget target;
  output Expression exp;
algorithm
  exp := match call
    local
      list<Expression> args;

    case Call.TYPED_CALL()
      algorithm
        args := list(SimplifyExp.simplifyExp(evalExp(arg, target))
          for arg in call.arguments);
      then
        if Function.isBuiltin(call.fn) then
          evalBuiltinCall(call.fn, args, target)
        else
          evalNormalCall(call.fn, args);

    case Call.UNTYPED_MAP_CALL()
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for mapcall", sourceInfo());
      then
        fail();

    else
      algorithm
        Error.addInternalError(getInstanceName() + " got untyped call", sourceInfo());
      then
        fail();

  end match;
end evalCall;

function evalBuiltinCall
  input Function fn;
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Absyn.Path fn_path = Function.nameConsiderBuiltin(fn);
algorithm
  result := match Absyn.pathFirstIdent(fn_path)
    case "abs" then evalBuiltinAbs(listHead(args));
    case "acos" then evalBuiltinAcos(listHead(args), target);
    case "array" then evalBuiltinArray(args);
    case "asin" then evalBuiltinAsin(listHead(args), target);
    case "atan2" then evalBuiltinAtan2(args);
    case "atan" then evalBuiltinAtan(listHead(args));
    case "cat" then evalBuiltinCat(listHead(args), listRest(args), target);
    case "ceil" then evalBuiltinCeil(listHead(args));
    case "cosh" then evalBuiltinCosh(listHead(args));
    case "cos" then evalBuiltinCos(listHead(args));
    case "cross" then evalBuiltinCross(args);
    case "der" then evalBuiltinDer(listHead(args));
    // TODO: Fix typing of diagonal so the argument isn't boxed.
    case "diagonal" then evalBuiltinDiagonal(Expression.unbox(listHead(args)));
    case "div" then evalBuiltinDiv(args, target);
    case "exp" then evalBuiltinExp(listHead(args));
    case "fill" then evalBuiltinFill(args);
    case "floor" then evalBuiltinFloor(listHead(args));
    case "identity" then evalBuiltinIdentity(listHead(args));
    case "integer" then evalBuiltinInteger(listHead(args));
    case "log10" then evalBuiltinLog10(listHead(args), target);
    case "log" then evalBuiltinLog(listHead(args), target);
    //case "matrix" then evalBuiltinMatrix(args);
    case "max" then evalBuiltinMax(args);
    case "min" then evalBuiltinMin(args);
    case "mod" then evalBuiltinMod(args);
    case "noEvent" then listHead(args); // No events during ceval, just return the argument.
    case "ones" then evalBuiltinOnes(args);
    case "product" then evalBuiltinProduct(listHead(args));
    case "promote" then evalBuiltinPromote(listGet(args,1),listGet(args,2));
    case "rem" then evalBuiltinRem(args, target);
    case "scalar" then evalBuiltinScalar(args);
    case "sign" then evalBuiltinSign(listHead(args));
    case "sinh" then evalBuiltinSinh(listHead(args));
    case "sin" then evalBuiltinSin(listHead(args));
    case "skew" then evalBuiltinSkew(listHead(args));
    case "sqrt" then evalBuiltinSqrt(listHead(args));
    case "sum" then evalBuiltinSum(listHead(args));
    //case "symmetric" then evalBuiltinSymmetric(args);
    case "tanh" then evalBuiltinTanh(listHead(args));
    case "tan" then evalBuiltinTan(listHead(args));
    case "transpose" then evalBuiltinTranspose(listHead(args));
    case "vector" then evalBuiltinVector(listHead(args));
    case "zeros" then evalBuiltinZeros(args);
    else
      algorithm
        Error.addInternalError(getInstanceName() + ": unimplemented case for " +
          Absyn.pathString(fn_path), sourceInfo());
      then
        fail();
  end match;
end evalBuiltinCall;

protected

function printUnboundError
  input EvalTarget target;
  input Expression exp;
algorithm
  () := match target
    case EvalTarget.DIMENSION()
      algorithm
        Error.addSourceMessage(Error.STRUCTURAL_PARAMETER_OR_CONSTANT_WITH_NO_BINDING,
          {Expression.toString(exp), InstNode.name(target.component)}, target.info);
      then
        fail();

    case EvalTarget.CONDITION()
      algorithm
        Error.addSourceMessage(Error.CONDITIONAL_EXP_WITHOUT_VALUE,
          {Expression.toString(exp)}, target.info);
      then
        fail();

    case EvalTarget.GENERIC()
      algorithm
        Error.addMultiSourceMessage(Error.UNBOUND_CONSTANT,
          {Expression.toString(exp)},
          {InstNode.info(ComponentRef.node(Expression.toCref(exp))), target.info});
      then
        fail();

    else ();
  end match;
end printUnboundError;

function evalNormalCall
  input Function fn;
  input list<Expression> args;
  output Expression result;
algorithm
  Error.addInternalError(getInstanceName() + ": IMPLEMENT ME", sourceInfo());
  fail();
end evalNormalCall;

function printWrongArgsError
  input String evalFunc;
  input list<Expression> args;
  input SourceInfo info;
algorithm
  Error.addInternalError(evalFunc + " got invalid arguments " +
    List.toString(args, Expression.toString, "", "(", ", ", ")", true), info);
end printWrongArgsError;

function evalBuiltinAbs
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.INTEGER() then Expression.INTEGER(abs(arg.value));
    case Expression.REAL() then Expression.REAL(abs(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAbs;

function evalBuiltinAcos
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x < -1.0 or x > 1.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "acos", "-1 <= x <= 1"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(acos(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAcos;

function evalBuiltinArray
  input list<Expression> args;
  output Expression result;
protected
  Type ty;
algorithm
  ty := Expression.typeOf(listHead(args));
  ty := Type.liftArrayLeft(ty, Dimension.fromInteger(listLength(args)));
  result := Expression.ARRAY(ty, args);
end evalBuiltinArray;

function evalBuiltinAsin
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x < -1.0 or x > 1.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "asin", "-1 <= x <= 1"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(asin(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAsin;

function evalBuiltinAtan2
  input list<Expression> args;
  output Expression result;
protected
  Real y, x;
algorithm
  result := match args
    case {Expression.REAL(value = y), Expression.REAL(value = x)}
      then Expression.REAL(atan2(y, x));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinAtan2;

function evalBuiltinAtan
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(atan(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinAtan;

function evalBuiltinCat
  input Expression argN;
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Integer n, nd;
  Type ty;
  list<Expression> es;
  list<Integer> dims;
algorithm
  Expression.INTEGER(n) := argN;
  ty := Expression.typeOf(listHead(args));
  nd := Type.dimensionCount(ty);
  if n > nd or n < 1 then
    if EvalTarget.hasInfo(target) then
      Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE, {String(n), "cat", "1 <= x <= " + String(nd)}, EvalTarget.getInfo(target));
    end if;
    fail();
  end if;
  (es,dims) := ExpressionSimplify.evalCat(n, args, getArrayContents=Expression.arrayElements, toString=Expression.toString);
  result := Expression.arrayFromList(es, Type.arrayElementType(ty), list(Dimension.fromInteger(d) for d in dims));
end evalBuiltinCat;

function evalBuiltinCeil
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(ceil(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinCeil;

function evalBuiltinCosh
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(cosh(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinCosh;

function evalBuiltinCos
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(cos(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinCos;

function evalBuiltinCross
  input list<Expression> args;
  output Expression result;
protected
  Real x1, x2, x3, y1, y2, y3;
  Expression z1, z2, z3;
algorithm
  result := match args
    case {Expression.ARRAY(elements = {Expression.REAL(x1), Expression.REAL(x2), Expression.REAL(x3)}),
          Expression.ARRAY(elements = {Expression.REAL(y1), Expression.REAL(y2), Expression.REAL(y3)})}
      algorithm
        z1 := Expression.REAL(x2 * y3 - x3 * y2);
        z2 := Expression.REAL(x3 * y1 - x1 * y3);
        z3 := Expression.REAL(x1 * y2 - x2 * y1);
      then
        Expression.ARRAY(Type.ARRAY(Type.REAL(), {Dimension.fromInteger(3)}), {z1, z2, z3});

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinCross;

function evalBuiltinDer
  input Expression arg;
  output Expression result;
algorithm
  result := Expression.fillType(Expression.typeOf(arg), Expression.REAL(0.0));
end evalBuiltinDer;

function evalBuiltinDiagonal
  input Expression arg;
  output Expression result;
protected
  Type elem_ty, row_ty;
  Expression zero;
  list<Expression> elems, row, rows = {};
  Integer n, i = 1;
algorithm
  result := match arg
    case Expression.ARRAY(elements = elems)
      algorithm
        n := listLength(elems);

        elem_ty := Expression.typeOf(listHead(elems));
        row_ty := Type.liftArrayLeft(elem_ty, Dimension.fromInteger(n));
        zero := Expression.makeZero(elem_ty);

        for e in listReverse(elems) loop
          row := {};

          for j in 2:i loop
            row := zero :: row;
          end for;

          row := e :: row;

          for j in i:n-1 loop
            row := zero :: row;
          end for;

          i := i + 1;
          rows := Expression.ARRAY(row_ty, row) :: rows;
        end for;
      then
        Expression.ARRAY(Type.liftArrayLeft(row_ty, Dimension.fromInteger(n)), rows);

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinDiagonal;

function evalBuiltinDiv
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Real rx, ry;
  Integer ix, iy;
algorithm
  result := match args
    case {Expression.INTEGER(ix), Expression.INTEGER(iy)}
      algorithm
        if iy == 0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.DIVISION_BY_ZERO,
              {String(ix), String(iy)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.INTEGER(intDiv(ix, iy));

    case {Expression.REAL(rx), Expression.REAL(ry)}
      algorithm
        if ry == 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.DIVISION_BY_ZERO,
              {String(rx), String(ry)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;

        rx := rx / ry;
      then
        Expression.REAL(if rx < 0.0 then ceil(rx) else floor(rx));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinDiv;

function evalBuiltinExp
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(exp(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinExp;

function evalBuiltinFill
  input list<Expression> args;
  output Expression result;
algorithm
  result := evalBuiltinFill2(listHead(args), listRest(args));
end evalBuiltinFill;

function evalBuiltinFill2
  input Expression fillValue;
  input list<Expression> dims;
  output Expression result = fillValue;
protected
  Integer dim_size;
  list<Expression> arr;
  Type arr_ty = Expression.typeOf(result);
algorithm
  for d in listReverse(dims) loop
    () := match d
      case Expression.INTEGER(value = dim_size) then ();
      else algorithm printWrongArgsError(getInstanceName(), {d}, sourceInfo()); then fail();
    end match;

    arr := list(result for e in 1:dim_size);
    arr_ty := Type.liftArrayLeft(arr_ty, Dimension.fromInteger(dim_size));
    result := Expression.ARRAY(arr_ty, arr);
  end for;
end evalBuiltinFill2;

function evalBuiltinFloor
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(floor(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinFloor;

function evalBuiltinIdentity
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.INTEGER()
      then Expression.makeIdentityMatrix(arg.value, Type.INTEGER());

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinIdentity;

function evalBuiltinInteger
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.INTEGER() then arg;
    case Expression.REAL() then Expression.INTEGER(realInt(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinInteger;

function evalBuiltinLog10
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x <= 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "log10", "x > 0"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(log10(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinLog10;

function evalBuiltinLog
  input Expression arg;
  input EvalTarget target;
  output Expression result;
protected
  Real x;
algorithm
  result := match arg
    case Expression.REAL(value = x)
      algorithm
        if x <= 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.ARGUMENT_OUT_OF_RANGE,
              {String(x), "log", "x > 0"}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(log(x));

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinLog;

function evalBuiltinMax
  input list<Expression> args;
  output Expression result;
protected
  Expression e1, e2;
  list<Expression> expl;
algorithm
  result := match args
    case {e1, e2} then evalBuiltinMax2(e1, e2);
    case {Expression.ARRAY(elements = expl)} then evalBuiltinMax2(e for e in expl);
    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinMax;

function evalBuiltinMax2
  input Expression exp1;
  input Expression exp2;
  output Expression result;
algorithm
  result := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then if exp1.value < exp2.value then exp2 else exp1;
    case (Expression.REAL(), Expression.REAL())
      then if exp1.value < exp2.value then exp2 else exp1;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then if exp1.value < exp2.value then exp2 else exp1;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then if exp1.index < exp2.index then exp2 else exp1;
    case (Expression.ARRAY(), Expression.ARRAY())
      then evalBuiltinMax2(evalBuiltinMax2(e for e in exp1.elements),
                           evalBuiltinMax2(e for e in exp2.elements));
    case (Expression.ARRAY(), _)
      then evalBuiltinMax2(evalBuiltinMax2(e for e in exp1.elements), exp2);
    else algorithm printWrongArgsError(getInstanceName(), {exp1, exp2}, sourceInfo()); then fail();
  end match;
end evalBuiltinMax2;

function evalBuiltinMin
  input list<Expression> args;
  output Expression result;
protected
  Expression e1, e2;
  list<Expression> expl;
algorithm
  result := match args
    case {e1, e2} then evalBuiltinMin2(e1, e2);
    case {Expression.ARRAY(elements = expl)} then evalBuiltinMin2(e for e in expl);
    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinMin;

function evalBuiltinMin2
  input Expression exp1;
  input Expression exp2;
  output Expression result;
algorithm
  result := match (exp1, exp2)
    case (Expression.INTEGER(), Expression.INTEGER())
      then if exp1.value > exp2.value then exp2 else exp1;
    case (Expression.REAL(), Expression.REAL())
      then if exp1.value > exp2.value then exp2 else exp1;
    case (Expression.BOOLEAN(), Expression.BOOLEAN())
      then if exp1.value > exp2.value then exp2 else exp1;
    case (Expression.ENUM_LITERAL(), Expression.ENUM_LITERAL())
      then if exp1.index > exp2.index then exp2 else exp1;
    case (Expression.ARRAY(), Expression.ARRAY())
      then evalBuiltinMin2(evalBuiltinMin2(e for e in exp1.elements),
                           evalBuiltinMin2(e for e in exp2.elements));
    case (Expression.ARRAY(), _)
      then evalBuiltinMin2(evalBuiltinMin2(e for e in exp1.elements), exp2);
    else algorithm printWrongArgsError(getInstanceName(), {exp1, exp2}, sourceInfo()); then fail();
  end match;
end evalBuiltinMin2;

function evalBuiltinMod
  input list<Expression> args;
  output Expression result;
protected
  Expression x, y;
algorithm
  {x, y} := args;

  result := match (x, y)
    case (Expression.INTEGER(), Expression.INTEGER())
      then Expression.INTEGER(mod(x.value, y.value));

    case (Expression.REAL(), Expression.REAL())
      then Expression.REAL(mod(x.value, y.value));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinMod;

function evalBuiltinOnes
  input list<Expression> args;
  output Expression result;
algorithm
  result := evalBuiltinFill2(Expression.INTEGER(1), args);
end evalBuiltinOnes;

function evalBuiltinProduct
  input Expression arg;
  output Expression result;
algorithm
  result := matchcontinue Type.arrayElementType(Expression.typeOf(arg))
    case Type.INTEGER() then Expression.INTEGER(Expression.fold(arg, evalBuiltinProductInt, 1));
    case Type.REAL() then Expression.REAL(Expression.fold(arg, evalBuiltinProductReal, 1.0));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end matchcontinue;
end evalBuiltinProduct;

function evalBuiltinProductInt
  input Expression exp;
  input output Integer result;
algorithm
  result := match exp
    case Expression.INTEGER() then result * exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinProductInt;

function evalBuiltinProductReal
  input Expression exp;
  input output Real result;
algorithm
  result := match exp
    case Expression.REAL() then result * exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinProductReal;

function evalBuiltinPromote
  input Expression arg, argN;
  output Expression result;
protected
  Integer n, numToPromote;
  Type ty;
algorithm
  Expression.INTEGER(n) := argN;
  ty := Expression.typeOf(arg);
  numToPromote := n - Type.dimensionCount(ty);
  result := evalBuiltinPromoteWork(arg, n);
end evalBuiltinPromote;

function evalBuiltinPromoteWork
  input Expression arg;
  input Integer n;
  output Expression result;
protected
  Expression exp;
  list<Expression> exps;
  Type ty;
algorithm
  Error.assertion(n >= 1, "Promote called with n<1", sourceInfo());
  if n == 1 then
    result := Expression.ARRAY(Type.liftArrayLeft(Expression.typeOf(arg),Dimension.fromInteger(1)), {arg});
    return;
  end if;
  result := match arg
    case Expression.ARRAY()
      algorithm
        (exps as (Expression.ARRAY(ty=ty)::_)) := list(evalBuiltinPromoteWork(e, n-1) for e in arg.elements);
      then Expression.ARRAY(Type.liftArrayLeft(ty,Dimension.fromInteger(listLength(arg.elements))), exps);
    else
      algorithm
        (exp as Expression.ARRAY(ty=ty)) := evalBuiltinPromoteWork(arg, n-1);
      then Expression.ARRAY(Type.liftArrayLeft(ty,Dimension.fromInteger(1)), {exp});
  end match;
end evalBuiltinPromoteWork;

function evalBuiltinRem
  input list<Expression> args;
  input EvalTarget target;
  output Expression result;
protected
  Expression x, y;
algorithm
  {x, y} := args;

  result := match (x, y)
    case (Expression.INTEGER(), Expression.INTEGER())
      algorithm
        if y.value == 0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.REM_ARG_ZERO, {String(x.value),
                String(y.value)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.INTEGER(x.value - (div(x.value, y.value) * y.value));

    case (Expression.REAL(), Expression.REAL())
      algorithm
        if y.value == 0.0 then
          if EvalTarget.hasInfo(target) then
            Error.addSourceMessage(Error.REM_ARG_ZERO,
              {String(x.value), String(y.value)}, EvalTarget.getInfo(target));
          end if;

          fail();
        end if;
      then
        Expression.REAL(x.value - (div(x.value, y.value) * y.value));

    else algorithm printWrongArgsError(getInstanceName(), args, sourceInfo()); then fail();
  end match;
end evalBuiltinRem;

function evalBuiltinScalar
  input list<Expression> args;
  output Expression result;
protected
  Expression exp = listHead(args);
algorithm
  result := match exp
    case Expression.ARRAY() then evalBuiltinScalar(exp.elements);
    else exp;
  end match;
end evalBuiltinScalar;

function evalBuiltinSign
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL()
      then Expression.INTEGER(if arg.value > 0 then 1 else if arg.value < 0 then -1 else 0);
    case Expression.INTEGER()
      then Expression.INTEGER(if arg.value > 0 then 1 else if arg.value < 0 then -1 else 0);
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSign;

function evalBuiltinSinh
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(sinh(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSinh;

function evalBuiltinSin
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(sin(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSin;

function evalBuiltinSkew
  input Expression arg;
  output Expression result;
protected
  Expression x1, x2, x3, y1, y2, y3;
  Type ty;
  Expression zero;
algorithm
  result := match arg
    case Expression.ARRAY(ty = ty, elements = {x1, x2, x3})
      algorithm
        zero := Expression.makeZero(Type.arrayElementType(ty));
        y1 := Expression.ARRAY(ty, {zero, Expression.negate(x3), x2});
        y2 := Expression.ARRAY(ty, {x3, zero, Expression.negate(x1)});
        y3 := Expression.ARRAY(ty, {Expression.negate(x2), x1, zero});
        ty := Type.liftArrayLeft(ty, Dimension.fromInteger(3));
      then
        Expression.ARRAY(ty, {y1, y2, y3});

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSkew;

function evalBuiltinSqrt
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(sqrt(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinSqrt;

function evalBuiltinSum
  input Expression arg;
  output Expression result;
algorithm
  result := matchcontinue Type.arrayElementType(Expression.typeOf(arg))
    case Type.INTEGER() then Expression.INTEGER(Expression.fold(arg, evalBuiltinSumInt, 0));
    case Type.REAL() then Expression.REAL(Expression.fold(arg, evalBuiltinSumReal, 0.0));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end matchcontinue;
end evalBuiltinSum;

function evalBuiltinSumInt
  input Expression exp;
  input output Integer result;
algorithm
  result := match exp
    case Expression.INTEGER() then result + exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinSumInt;

function evalBuiltinSumReal
  input Expression exp;
  input output Real result;
algorithm
  result := match exp
    case Expression.REAL() then result + exp.value;
    case Expression.ARRAY() then result;
    else fail();
  end match;
end evalBuiltinSumReal;

function evalBuiltinTanh
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(tanh(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinTanh;

function evalBuiltinTan
  input Expression arg;
  output Expression result;
algorithm
  result := match arg
    case Expression.REAL() then Expression.REAL(tan(arg.value));
    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinTan;

function evalBuiltinTranspose
  input Expression arg;
  output Expression result;
protected
  Dimension dim1, dim2;
  list<Dimension> rest_dims;
  Type ty;
  list<Expression> arr;
  list<list<Expression>> arrl;
algorithm
  result := match arg
    case Expression.ARRAY(ty = Type.ARRAY(elementType = ty,
                                          dimensions = dim1 :: dim2 :: rest_dims),
                          elements = arr)
      algorithm
        arrl := list(Expression.arrayElements(e) for e in arr);
        arrl := List.transposeList(arrl);
        ty := Type.liftArrayLeft(ty, dim1);
        arr := list(Expression.ARRAY(ty, expl) for expl in arrl);
        ty := Type.liftArrayLeft(ty, dim2);
      then
        Expression.ARRAY(ty, arr);

    else algorithm printWrongArgsError(getInstanceName(), {arg}, sourceInfo()); then fail();
  end match;
end evalBuiltinTranspose;

function evalBuiltinVector
  input Expression arg;
  output Expression result;
protected
  list<Expression> expl;
  Type ty;
algorithm
  expl := Expression.fold(arg, evalBuiltinVector2, {});
  ty := Type.liftArrayLeft(Type.arrayElementType(Expression.typeOf(arg)),
    Dimension.fromInteger(listLength(expl)));
  result := Expression.ARRAY(ty, listReverse(expl));
end evalBuiltinVector;

function evalBuiltinVector2
  input Expression exp;
  input output list<Expression> expl;
algorithm
  expl := match exp
    case Expression.ARRAY() then expl;
    else exp :: expl;
  end match;
end evalBuiltinVector2;

function evalBuiltinZeros
  input list<Expression> args;
  output Expression result;
algorithm
  result := evalBuiltinFill2(Expression.INTEGER(0), args);
end evalBuiltinZeros;

annotation(__OpenModelica_Interface="frontend");
end NFCeval;
