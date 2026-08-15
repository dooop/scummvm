/* ScummVM - Graphic Adventure Engine
 *
 * This override header fixes a missing class declaration in the upstream
 * generated file without modifying the submodule.
 */

#ifndef TITANIC_PET_VAL_BASE_H
#define TITANIC_PET_VAL_BASE_H

namespace Titanic {

class CPetValBase {
protected:
	int _field4;
	int _field8;
	int _fieldC;
	int _field10;
	int _field14;
public:
	CPetValBase();
};

} // End of namespace Titanic

#endif /* TITANIC_PET_VAL_BASE_H */
