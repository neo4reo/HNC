#include <hn/lib.hpp>

struct hnMain_impl
{
	struct main_impl
	{
		int x;
		int a;

		bool y(int z)
		{
			return ff::less(x + a, z);
		};
	};

	static std::list<int> main(int x, int z, std::list<int> l)
	{
		typedef main_impl local;
		local impl = { x, z + 1 };
		return ff::filter<int>(hn::bind(impl, &local::y), l);
	};
};

ff::IO<void> hnMain()
{
	typedef hnMain_impl local;
	return ff::print("foo");
};
